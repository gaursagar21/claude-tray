import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var isRunning   = false
    @Published var requests: [RequestLog] = []
    @Published var port: UInt16 = 3666
    @Published var errorMessage: String? = nil

    private var proxyServer: ProxyServer?
    private(set) var storage: Storage?

    init() {
        setupStorage()
        startProxy()
    }

    // MARK: - Storage

    private func setupStorage() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeTray")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("requests.db")
        storage = try? Storage(path: dbURL.path)
        if let s = storage {
            requests = s.fetchRequests()
        }
    }

    // MARK: - Proxy lifecycle

    func startProxy() {
        guard let storage else { return }
        proxyServer = ProxyServer(port: port, storage: storage) { [weak self] log in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Disable animation for streaming inserts — prevents layout thrashing.
                var txn = Transaction()
                txn.disablesAnimations = true
                withTransaction(txn) {
                    self.requests.insert(log, at: 0)
                    if self.requests.count > 200 { self.requests.removeLast() }
                }
            }
        }
        do {
            try proxyServer?.start()
            isRunning = true
            errorMessage = nil
        } catch {
            isRunning = false
            errorMessage = error.localizedDescription
        }
    }

    func stopProxy() {
        proxyServer?.stop()
        proxyServer = nil
        isRunning = false
    }

    func clearAll() {
        storage?.deleteAll()
        requests.removeAll()
    }

    func refresh() {
        guard let storage else { return }
        requests = storage.fetchRequests()
    }
}
