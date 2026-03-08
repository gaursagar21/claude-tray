import SwiftUI
import AppKit

@main
struct ClaudeTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .symbolRenderingMode(.monochrome)
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Claude Monitor", id: "monitor") {
            RequestsView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1100, height: 660)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — tray only.
        NSApp.setActivationPolicy(.accessory)
    }
}
