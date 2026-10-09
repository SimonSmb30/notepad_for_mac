import AppKit
import SwiftUI

@main
struct NotepadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var workspace = Workspace.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Schon vor dem ersten Fenster nötig: Beim Start per Datei aus dem Finder
        // legt SwiftUI keines an.
        let _ = workspace.openWindowAction = openWindow
        WindowGroup(id: Workspace.windowGroupID) {
            WindowRootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 520)
        .restorationBehavior(.disabled)
        // Dateien aus dem Finder landen als Tab im vorhandenen Fenster statt in einem neuen.
        .handlesExternalEvents(matching: [])
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

    /// Dateien, die der Finder per Doppelklick oder „Öffnen mit“ übergibt.
    func application(_ application: NSApplication, open urls: [URL]) {
        Workspace.shared.open(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Workspace.shared.confirmQuit() ? .terminateNow : .terminateCancel
    }
}
