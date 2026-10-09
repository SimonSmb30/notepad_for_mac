import AppKit
import SwiftUI

@main
struct NotepadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var workspace = Workspace.shared

    var body: some Scene {
        WindowGroup(id: Workspace.windowGroupID) {
            WindowRootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 520)
        .restorationBehavior(.disabled)
        .commands {
            AppCommands(shortcuts: workspace.shortcuts)
        }

        Settings {
            SettingsView()
                .environment(Workspace.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Das Kürzel für „Tab schließen“ (Standard ⌘W) schließt den aktiven Tab
        // statt des ganzen Fensters.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                let workspace = Workspace.shared
                guard workspace.recordingAction == nil,
                      Shortcut(event: event) == workspace.shortcut(for: .closeTab) else { return false }
                if let store = Workspace.shared.liveWindows.first(where: { $0.window === NSApp.keyWindow }) {
                    store.closeCurrent()
                } else {
                    // Einstellungen, Schriftdialog und Ähnliches schließen ganz normal.
                    NSApp.keyWindow?.performClose(nil)
                }
                return true
            }
            return handled ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Workspace.shared.confirmQuit() ? .terminateNow : .terminateCancel
    }
}
