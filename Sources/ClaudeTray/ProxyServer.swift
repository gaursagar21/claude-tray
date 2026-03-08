import Foundation
import Network

// Long-timeout URLSession shared for all Anthropic forwarding.
private let proxySession: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest  = 600
    cfg.timeoutIntervalForResource = 600
    // Let URLSession decompress automatically; we'll forward uncompressed.
    cfg.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
    return URLSession(configuration: cfg)
}()

final class ProxyServer: @unchecked Sendable {
    private var listener: NWListener?
    let port: UInt16
    private let storage: Storage
    private let onRequest: (RequestLog) -> Void

    init(port: UInt16 = 3001, storage: Storage, onRequest: @escaping (RequestLog) -> Void) {
        self.port = port
        self.storage = storage
        self.onRequest = onRequest
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ProxyError.invalidPort
        }
        listener = try NWListener(using: params, on: nwPort)
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { await self.handle(conn) }
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Per-connection handler

    private func handle(_ conn: NWConnection) async {
        conn.start(queue: .global(qos: .userInitiated))
        defer { conn.cancel() }

        do {
            let (method, path, headers, body) = try await readHTTPRequest(from: conn)

            if path == "/health" {
                try await send(conn, httpStatus: 200, contentType: "application/json", body: Data("{\"ok\":true}".utf8))
            } else {
                // Forward everything else to Anthropic transparently.
                await forward(method: method, path: path, headers: headers, body: body, to: conn)
            }
        } catch {
            // Connection closed or parse error — ignore silently.
        }
    }

    // MARK: - Forward to Anthropic

    private func forward(method: String, path: String, headers: [String: String], body: Data, to conn: NWConnection) async {
        let startTime = Date()
        let requestId = randomID()

        guard let url = URL(string: "https://api.anthropic.com\(path)") else { return }
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = method
        urlReq.httpBody = body.isEmpty ? nil : body

        // Pass through all headers except hop-by-hop ones.
        let hopByHop: Set<String> = ["connection", "keep-alive", "transfer-encoding",
                                      "te", "trailers", "upgrade", "proxy-authorization",
                                      "proxy-authenticate", "accept-encoding", "host"]
        for (key, val) in headers where !hopByHop.contains(key.lowercased()) {
            urlReq.setValue(val, forHTTPHeaderField: key)
        }

        // Parse body for metadata (best-effort; non-messages endpoints may not have these).
        let json        = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let isStreaming = json["stream"] as? Bool ?? false
        let model       = json["model"] as? String ?? path

        do {
            if isStreaming {
                let (asyncBytes, response) = try await proxySession.bytes(for: urlReq)
                guard let http = response as? HTTPURLResponse else { return }

                // Send response headers to client.
                let resHeaders = "HTTP/1.1 \(http.statusCode) \(statusText(http.statusCode))\r\n" +
                                 "Content-Type: text/event-stream\r\n" +
                                 "Cache-Control: no-cache\r\n" +
                                 "Connection: close\r\n\r\n"
                try await write(Data(resHeaders.utf8), to: conn)

                // Pipe SSE bytes, buffer per line for efficiency.
                var accumulated = Data()
                var lineBuf    = Data()

                for try await byte in asyncBytes {
                    lineBuf.append(byte)
                    accumulated.append(byte)
                    if byte == UInt8(ascii: "\n") {
                        try await write(lineBuf, to: conn)
                        lineBuf.removeAll(keepingCapacity: true)
                    }
                }
                if !lineBuf.isEmpty { try await write(lineBuf, to: conn) }

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                let (inp, out) = tokensFromSSE(accumulated)
                let log = RequestLog(id: requestId, timestamp: startTime, model: model,
                                     inputTokens: inp, outputTokens: out,
                                     isStreaming: true, durationMs: duration, statusCode: http.statusCode)
                let reqBodyStr = String(data: body, encoding: .utf8) ?? ""
                let resBodyStr = String(data: accumulated, encoding: .utf8) ?? ""
                storage.save(log: log, requestBody: reqBodyStr, responseBody: resBodyStr)
                onRequest(log)

            } else {
                let (data, response) = try await proxySession.data(for: urlReq)
                guard let http = response as? HTTPURLResponse else { return }

                let resHeaders = "HTTP/1.1 \(http.statusCode) \(statusText(http.statusCode))\r\n" +
                                 "Content-Type: application/json\r\n" +
                                 "Content-Length: \(data.count)\r\n" +
                                 "Connection: close\r\n\r\n"
                var out = Data(resHeaders.utf8)
                out.append(data)
                try await write(out, to: conn)

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                let (inp, oup) = tokensFromJSON(data)
                let log = RequestLog(id: requestId, timestamp: startTime, model: model,
                                     inputTokens: inp, outputTokens: oup,
                                     isStreaming: false, durationMs: duration, statusCode: http.statusCode)
                let reqBodyStr = String(data: body, encoding: .utf8) ?? ""
                let resBodyStr = String(data: data, encoding: .utf8) ?? ""
                storage.save(log: log, requestBody: reqBodyStr, responseBody: resBodyStr)
                onRequest(log)
            }
        } catch {
            let errHeaders = "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            try? await write(Data(errHeaders.utf8), to: conn)
        }
    }

    // MARK: - HTTP reading

    private func readHTTPRequest(from conn: NWConnection) async throws -> (String, String, [String: String], Data) {
        var buf = Data()

        // Accumulate until we have the full headers.
        while !buf.contains(separator: "\r\n\r\n") {
            buf.append(try await readChunk(from: conn))
        }

        guard let headerEndRange = buf.range(of: Data("\r\n\r\n".utf8)) else {
            throw ProxyError.malformedRequest
        }

        let headerData = buf[buf.startIndex ..< headerEndRange.lowerBound]
        let headerStr  = String(data: headerData, encoding: .utf8) ?? ""
        var body       = Data(buf[headerEndRange.upperBound...])

        // Parse request line + headers.
        var lines      = headerStr.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst()
        let parts       = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { throw ProxyError.malformedRequest }
        let method = parts[0]
        let path   = parts[1]

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = val
        }

        // Read remaining body bytes if Content-Length says we need more.
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        while body.count < contentLength {
            body.append(try await readChunk(from: conn))
        }

        return (method, path, headers, Data(body.prefix(contentLength)))
    }

    // MARK: - NWConnection helpers

    private func readChunk(from conn: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                if let data, !data.isEmpty { cont.resume(returning: data); return }
                if isComplete { cont.resume(throwing: ProxyError.connectionClosed); return }
                cont.resume(returning: Data())
            }
        }
    }

    private func write(_ data: Data, to conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func send(_ conn: NWConnection, httpStatus: Int, contentType: String, body: Data) async throws {
        let headers = "HTTP/1.1 \(httpStatus) \(statusText(httpStatus))\r\n" +
                      "Content-Type: \(contentType)\r\n" +
                      "Content-Length: \(body.count)\r\n" +
                      "Connection: close\r\n\r\n"
        var out = Data(headers.utf8)
        out.append(body)
        try await write(out, to: conn)
    }
}

// MARK: - Token extraction

private func tokensFromSSE(_ data: Data) -> (Int, Int) {
    var input = 0, output = 0
    let text = String(data: data, encoding: .utf8) ?? ""
    for line in text.components(separatedBy: "\n") {
        guard line.hasPrefix("data: "),
              let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any]
        else { continue }
        if let usage = json["usage"] as? [String: Any] {
            input  = usage["input_tokens"]  as? Int ?? input
            output = usage["output_tokens"] as? Int ?? output
        }
        if let delta = (json["message"] as? [String: Any])?["usage"] as? [String: Any] {
            input  = delta["input_tokens"]  as? Int ?? input
            output = delta["output_tokens"] as? Int ?? output
        }
    }
    return (input, output)
}

private func tokensFromJSON(_ data: Data) -> (Int, Int) {
    guard let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let usage = json["usage"] as? [String: Any]
    else { return (0, 0) }
    let input  = usage["input_tokens"]  as? Int ?? 0
    let output = usage["output_tokens"] as? Int ?? 0
    return (input, output)
}

// MARK: - Misc helpers


private func statusText(_ code: Int) -> String {
    switch code {
    case 200: "OK"
    case 400: "Bad Request"
    case 401: "Unauthorized"
    case 404: "Not Found"
    case 429: "Too Many Requests"
    case 500: "Internal Server Error"
    case 502: "Bad Gateway"
    default: "Unknown"
    }
}

private func randomID() -> String {
    var bytes = [UInt8](repeating: 0, count: 8)
    _ = SecRandomCopyBytes(kSecRandomDefault, 8, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
}

private extension Data {
    func contains(separator: String) -> Bool {
        range(of: Data(separator.utf8)) != nil
    }
}

enum ProxyError: Error {
    case invalidPort
    case malformedRequest
    case connectionClosed
}
