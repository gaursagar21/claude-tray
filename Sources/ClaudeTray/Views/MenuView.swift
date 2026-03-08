import SwiftUI
import AppKit

struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow

    var body: some View {
        // Status header (non-interactive)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(appState.isRunning ? "Proxy running" : "Proxy stopped")
                    .font(.system(size: 13, weight: .medium))
            }
            if appState.isRunning {
                Text("\(appState.requests.count) API calls captured  ·  localhost:\(appState.port, format: .number.grouping(.never))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 13)
            }
            if let err = appState.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 13)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)

        Divider()

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "monitor")
        } label: {
            Label("Open Monitor", systemImage: "chart.bar")
        }

        Divider()

        if appState.isRunning {
            Button {
                appState.stopProxy()
            } label: {
                Label("Stop Proxy", systemImage: "stop.circle")
            }
        } else {
            Button {
                appState.startProxy()
            } label: {
                Label("Start Proxy", systemImage: "play.circle")
            }
        }

        Button(role: .destructive) {
            appState.clearAll()
        } label: {
            Label("Clear Requests", systemImage: "trash")
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
