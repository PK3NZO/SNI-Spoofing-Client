import SwiftUI

@main
struct SniSpoofingMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var languageStore = AppLanguageStore.shared
    @StateObject private var tunnelController = TunnelController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(languageStore)
                .environmentObject(tunnelController)
                .environment(\.locale, languageStore.selectedLanguage.locale)
                .environment(\.layoutDirection, languageStore.selectedLanguage.isRTL ? .rightToLeft : .leftToRight)
                .onAppear {
                    appDelegate.tunnelController = tunnelController
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var tunnelController: TunnelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Attempt to find the window and set delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = NSApplication.shared.windows.first {
                window.delegate = self
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Confirm Exit"
        
        // Refresh controller state check
        let isActive = tunnelController?.isConnected == true || tunnelController?.isBusy == true
        
        if isActive {
            alert.informativeText = "The proxy is currently active. Quitting will disconnect the tunnel and reset system settings. Are you sure?"
        } else {
            alert.informativeText = "Are you sure you want to quit the application?"
        }
        
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = isActive ? .warning : .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let controller = tunnelController {
                controller.disconnectEmbeddedFlow()
            }
            return .terminateNow
        } else {
            return .terminateCancel
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Instead of showing a dialog here, just trigger app termination
        // This ensures applicationShouldTerminate is called once.
        NSApplication.shared.terminate(nil)
        return false // Cancel the window-only close so termination can handle it
    }
}
