import AppKit
import Observation
import UniformTypeIdentifiers

/// Zustand eines Fensters: seine Tabs und der aktive Tab.
@MainActor
@Observable
final class WindowStore: Identifiable {
    let id: UUID
    private(set) var documents: [TextDocument]
    var selectedID: TextDocument.ID
    var isTabSearchPresented = false

    @ObservationIgnored weak var window: NSWindow?
    /// Position für ein Fenster, das durch Herausziehen eines Tabs entsteht.
    @ObservationIgnored var initialTopLeft: NSPoint?
    @ObservationIgnored private var closeTarget: ActionTarget?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Höhe der Tab-Leiste; die Fensterpunkte werden darin vertikal zentriert.
    static let tabBarHeight: CGFloat = 40
    /// Platz links in der Tab-Leiste für Schließen, Minimieren und Zoomen.
    static let windowButtonsWidth: CGFloat = 86
    /// Abstand des roten Punkts zum linken Fensterrand, wie `centerWindowButtons` ihn setzt.
    private(set) var windowButtonMargin: CGFloat = 13
    /// Größe eines Fensterpunkts und Abstand von einem zum nächsten, an den echten gemessen.
    private(set) var windowButtonSize = CGSize(width: 14, height: 16)
    private(set) var windowButtonSpacing: CGFloat = 20
    /// Im Vollbild zeichnet die Tab-Leiste die Fensterpunkte selbst.
    private(set) var isFullScreen = false
    @ObservationIgnored private weak var fullScreenTitlebarWindow: NSWindow?

    private var workspace: Workspace { .shared }

    init(id: UUID = UUID(), documents: [TextDocument]? = nil) {
        let documents = documents ?? [TextDocument()]
        self.id = id
        self.documents = documents
        selectedID = documents[0].id
    }

    var current: TextDocument? {
        documents.first { $0.id == selectedID }
    }

    // MARK: - Fenster

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        if let initialTopLeft {
            window.setFrameTopLeftPoint(initialTopLeft)
            self.initialTopLeft = nil
        }

        isFullScreen = window.styleMask.contains(.fullScreen)
        centerWindowButtons()
        // AppKit setzt die Punkte bei jedem Neuaufbau der Titelleiste zurück.
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
            NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
        ]
        observers = names.map { name in
            observe(name, on: window) { $0.centerWindowButtons() }
        }
        observers += [
            observe(NSWindow.willEnterFullScreenNotification, on: window) { $0.isFullScreen = true },
            observe(NSWindow.didEnterFullScreenNotification, on: window) { $0.hideFullScreenTitlebar() },
            // Beim Einfahren der Menüleiste baut AppKit die Titelleiste teils neu auf.
            observe(NSWindow.didUpdateNotification, on: window) { $0.hideFullScreenTitlebar() },
            observe(NSWindow.willExitFullScreenNotification, on: window) {
                $0.showFullScreenTitlebar()
                $0.isFullScreen = false
            },
        ]
        hideFullScreenTitlebar()

        // Der rote Punkt fragt erst nach ungespeicherten Änderungen, bevor das Fenster schließt.
        let target = ActionTarget { [weak self] in self?.closeWindow() }
        closeTarget = target
        let closeButton = window.standardWindowButton(.closeButton)
        closeButton?.target = target
        closeButton?.action = #selector(ActionTarget.fire)
    }

    private func observe(_ name: Notification.Name, on window: NSWindow,
                         _ action: @escaping @MainActor (WindowStore) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    /// Im Vollbild lagert AppKit die Titelleiste in ein eigenes Fenster aus, das
    /// mit der Menüleiste einfährt und die Tab-Leiste verdecken würde.
    private func hideFullScreenTitlebar() {
        guard isFullScreen, let window,
              let titlebarWindow = window.standardWindowButton(.closeButton)?.window,
              titlebarWindow !== window else { return }
        fullScreenTitlebarWindow = titlebarWindow
        if titlebarWindow.contentView?.isHidden == false { titlebarWindow.contentView?.isHidden = true }
        if !titlebarWindow.ignoresMouseEvents { titlebarWindow.ignoresMouseEvents = true }
    }

    private func showFullScreenTitlebar() {
        fullScreenTitlebarWindow?.contentView?.isHidden = false
        fullScreenTitlebarWindow?.ignoresMouseEvents = false
        fullScreenTitlebarWindow = nil
    }

    private func centerWindowButtons() {
        // Im Vollbild liegen die Punkte nicht in diesem Fenster.
        guard let window, !isFullScreen else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let close = buttons.first, let titlebar = close.superview else { return }

        // Der Abstand zum linken Rand soll so groß sein wie der nach oben und unten.
        let margin = (Self.tabBarHeight - close.frame.height) / 2
        let shift = margin - close.frame.minX
        if windowButtonMargin != margin { windowButtonMargin = margin }
        if windowButtonSize != close.frame.size { windowButtonSize = close.frame.size }
        if buttons.count > 1 {
            let spacing = buttons[1].frame.minX - close.frame.minX
            if windowButtonSpacing != spacing { windowButtonSpacing = spacing }
        }
        // Die Titelleiste ist niedriger als die Tab-Leiste und hängt oben am Fenster.
        let y = titlebar.isFlipped ? margin : titlebar.bounds.height - margin - close.frame.height
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: button.frame.minX + shift, y: y))
        }
    }

    /// Fragt für jeden geänderten Tab nach. `false` heißt: abgebrochen.
    func confirmCloseAll() -> Bool {
        for document in documents where document.isDirty {
            selectedID = document.id
            window?.makeKeyAndOrderFront(nil)
            guard confirmDiscard(document) else { return false }
        }
        return true
    }

    func closeWindow() {
        guard confirmCloseAll() else { return }
        documents.compactMap(\.url).reversed().forEach(workspace.noteClosed)
        tearDown()
    }

    private func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        workspace.remove(self)
        window?.close()
        // Mit dem letzten Notepad-Fenster endet die App, auch wenn die
        // Einstellungen noch offen sind.
        if workspace.liveWindows.isEmpty {
            NSApp.terminate(nil)
        }
    }

    func focus(_ document: TextDocument) {
        selectedID = document.id
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Datei

    func newDocument() {
        let document = TextDocument()
        documents.append(document)
        selectedID = document.id
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open)
    }

    func open(_ url: URL) {
        if let existing = workspace.locate(url) {
            existing.store.focus(existing.document)
            return
        }
        guard let text = Self.read(url) else {
            workspace.showError(String(localized: "“\(url.lastPathComponent)” could not be read as text."))
            return
        }
        let document = TextDocument(url: url, text: text)
        if let current, current.isPristine, let index = documents.firstIndex(where: { $0.id == current.id }) {
            documents[index] = document
        } else {
            documents.append(document)
        }
        selectedID = document.id
        workspace.noteOpened(url)
    }

    @discardableResult
    func save(_ document: TextDocument) -> Bool {
        guard let url = document.url else { return saveAs(document) }
        return write(document, to: url)
    }

    @discardableResult
    func saveAs(_ document: TextDocument) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = document.url?.lastPathComponent ?? document.title + ".txt"
        panel.directoryURL = document.url?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(document, to: url)
    }

    func saveCurrent() {
        if let current { save(current) }
    }

    func saveCurrentAs() {
        if let current { saveAs(current) }
    }

    func printCurrent() {
        current?.textView?.printView(nil)
    }

    func close(_ document: TextDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        selectedID = document.id
        guard confirmDiscard(document) else { return }
        if let url = document.url {
            workspace.noteClosed(url)
        }

        documents.remove(at: index)
        if documents.isEmpty {
            // Der letzte Tab schließt das Fenster; war es das letzte Fenster,
            // beendet sich damit auch die App.
            tearDown()
            return
        }
        selectedID = documents[min(index, documents.count - 1)].id
    }

    func closeCurrent() {
        if let current { close(current) }
    }

    /// Löst einen Tab aus diesem Fenster und öffnet ihn in einem eigenen.
    func detach(_ document: TextDocument) {
        guard documents.count > 1, let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents.remove(at: index)
        if selectedID == document.id {
            selectedID = documents[min(index, documents.count - 1)].id
        }
        workspace.openWindow(with: document, near: NSEvent.mouseLocation)
    }

    private func confirmDiscard(_ document: TextDocument) -> Bool {
        guard document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Do you want to save the changes to “\(document.title)”?")
        alert.informativeText = String(localized: "Your changes will be lost if you don’t save them.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Don’t Save"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save(document)
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func write(_ document: TextDocument, to url: URL) -> Bool {
        do {
            try document.text.write(to: url, atomically: true, encoding: .utf8)
            document.url = url
            document.isDirty = false
            workspace.noteOpened(url)
            return true
        } catch {
            workspace.showError(String(localized: "“\(url.lastPathComponent)” could not be saved. \(error.localizedDescription)"))
            return false
        }
    }

    private static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .windowsCP1252)
    }

    // MARK: - Bearbeiten

    private var activeTextView: NSTextView? {
        guard let textView = current?.textView else { return nil }
        textView.window?.makeFirstResponder(textView)
        return textView
    }

    func find() { performFind(.showFindInterface) }
    func replace() { performFind(.showReplaceInterface) }

    private func performFind(_ action: NSTextFinder.Action) {
        // Die Suchleiste erwartet einen Absender, dessen `tag` die Aktion nennt.
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        activeTextView?.performFindPanelAction(sender)
    }

    func insertTimestamp() {
        guard let textView = activeTextView else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd.MM.yyyy"
        textView.insertText(formatter.string(from: Date()), replacementRange: textView.selectedRange())
    }

    func goToLine() {
        guard let textView = activeTextView else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = String(localized: "Line Number")

        let alert = NSAlert()
        alert.messageText = String(localized: "Go to Line")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Go"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let target = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), target > 0 else { return }

        let string = textView.string as NSString
        var line = 1
        var location = 0
        while line < target, location < string.length {
            location = NSMaxRange(string.lineRange(for: NSRange(location: location, length: 0)))
            line += 1
        }
        // Liegt die Zeile hinter dem Ende, landet der Cursor am Textende.
        let range = NSRange(location: min(location, string.length), length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.window?.makeFirstResponder(textView)
    }
}

/// Ziel für AppKit-Aktionen, die eine Closure auslösen sollen.
@MainActor
final class ActionTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() {
        handler()
    }
}
