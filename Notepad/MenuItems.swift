import AppKit
import SwiftUI

// Die Menüeinträge sind einmal definiert und hängen sowohl in der Menüzeile
// im Fenster als auch in der Mac-Menüleiste. `store` liefert das Fenster,
// auf das der Befehl wirkt.

struct FileOpenItems: View {
    let store: () -> WindowStore?
    let shortcuts: [ShortcutAction: Shortcut]

    var body: some View {
        Button(ShortcutAction.newTab.menuTitle) { store()?.newDocument() }
            .shortcut(.newTab, shortcuts)
        Button(ShortcutAction.newWindow.menuTitle) { Workspace.shared.newWindow() }
            .shortcut(.newWindow, shortcuts)
        Button(ShortcutAction.open.menuTitle) { store()?.openDocument() }
            .shortcut(.open, shortcuts)
    }
}

struct FileSaveItems: View {
    let store: () -> WindowStore?
    let shortcuts: [ShortcutAction: Shortcut]

    var body: some View {
        Button(ShortcutAction.save.menuTitle) { store()?.saveCurrent() }
            .shortcut(.save, shortcuts)
        Button(ShortcutAction.saveAs.menuTitle) { store()?.saveCurrentAs() }
            .shortcut(.saveAs, shortcuts)
        Button(ShortcutAction.print.menuTitle) { store()?.printCurrent() }
            .shortcut(.print, shortcuts)
    }
}

struct EditExtraItems: View {
    let store: () -> WindowStore?
    let shortcuts: [ShortcutAction: Shortcut]

    var body: some View {
        Button(ShortcutAction.find.menuTitle) { store()?.find() }
            .shortcut(.find, shortcuts)
        Button(ShortcutAction.replace.menuTitle) { store()?.replace() }
            .shortcut(.replace, shortcuts)
        Button(ShortcutAction.goToLine.menuTitle) { store()?.goToLine() }
            .shortcut(.goToLine, shortcuts)
        Divider()
        Button(ShortcutAction.timestamp.menuTitle) { store()?.insertTimestamp() }
            .shortcut(.timestamp, shortcuts)
    }
}

struct ViewItems: View {
    let store: () -> WindowStore?
    let shortcuts: [ShortcutAction: Shortcut]

    var body: some View {
        Button(ShortcutAction.zoomIn.menuTitle) { Workspace.shared.zoomIn() }
            .shortcut(.zoomIn, shortcuts)
        Button(ShortcutAction.zoomOut.menuTitle) { Workspace.shared.zoomOut() }
            .shortcut(.zoomOut, shortcuts)
        Button(ShortcutAction.resetZoom.menuTitle) { Workspace.shared.resetZoom() }
            .shortcut(.resetZoom, shortcuts)
        Divider()
        Button(ShortcutAction.tabSearch.menuTitle) { store()?.isTabSearchPresented = true }
            .shortcut(.tabSearch, shortcuts)
    }
}

struct AppCommands: Commands {
    /// Als Wert übergeben, damit die Menüleiste bei einer Änderung neu aufgebaut wird.
    let shortcuts: [ShortcutAction: Shortcut]
    private let store: () -> WindowStore? = { Workspace.shared.activeStore }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            FileOpenItems(store: store, shortcuts: shortcuts)
        }
        CommandGroup(replacing: .saveItem) {
            FileSaveItems(store: store, shortcuts: shortcuts)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            EditExtraItems(store: store, shortcuts: shortcuts)
        }
        CommandGroup(before: .sidebar) {
            ViewItems(store: store, shortcuts: shortcuts)
            Divider()
        }
        CommandGroup(replacing: .help) {
            // Reiner Hinweistext, kein anklickbarer Befehl.
            Text("V\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") a Simon Schäfer Application")
        }
    }
}
