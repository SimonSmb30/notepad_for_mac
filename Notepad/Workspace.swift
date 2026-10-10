import AppKit
import Observation
import SwiftUI

/// Eine zuletzt geschlossene Datei für die Tab-Suche.
struct ClosedTab: Identifiable, Equatable {
    let url: URL
    let date: Date

    var id: String { url.path }
}

/// Alles, was fensterübergreifend gilt: die offenen Fenster, die Einstellungen
/// und die Liste der zuletzt geschlossenen Dateien.
@MainActor
@Observable
final class Workspace {
    static let shared = Workspace()

    @ObservationIgnored private(set) var windows: [WindowStore] = []
    @ObservationIgnored private var pendingStores: [WindowStore] = []
    /// Dateien aus dem Finder, die beim Start eintreffen, bevor ein Fenster existiert.
    @ObservationIgnored private var pendingURLs: [URL] = []
    @ObservationIgnored var openWindowAction: OpenWindowAction?

    private(set) var font: NSFont
    private(set) var wordWrap: Bool
    private(set) var zoom: CGFloat = 1
    /// Ob HTML-Dateien in der Vorschau Skripte ausführen bzw. aus dem Internet laden dürfen.
    private(set) var previewAllowsScripts: Bool
    private(set) var previewAllowsNetwork: Bool
    private(set) var recentlyClosed: [ClosedTab]

    private(set) var shortcuts: [ShortcutAction: Shortcut]
    /// Der Befehl, für den gerade eine neue Tastenkombination aufgenommen wird.
    private(set) var recordingAction: ShortcutAction?
    /// Hinweis unter der Kürzel-Liste, etwa bei einer schon vergebenen Kombination.
    private(set) var shortcutMessage: String?
    @ObservationIgnored private var recordingMonitor: Any?

    private(set) var mode: AppearanceMode
    private(set) var backgroundColor: NSColor
    private(set) var menuColor: NSColor
    private(set) var textColor: NSColor
    private(set) var barColor: NSColor

    static let windowGroupID = "editor"

    private enum Keys {
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let wordWrap = "wordWrap"
        static let recentlyClosed = "recentlyClosed"
        static let appearanceMode = "appearanceMode"
        static let shortcuts = "shortcuts"
        static let menuColor = "menuColor"
        static let backgroundColor = "backgroundColor"
        static let textColor = "textColor"
        static let barColor = "barColor"
        static let previewAllowsScripts = "previewAllowsScripts"
        static let previewAllowsNetwork = "previewAllowsNetwork"
    }

    private static let defaultFont = NSFont(name: "Menlo", size: 13)
        ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let recentlyClosedLimit = 10

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.wordWrap: true, Keys.previewAllowsScripts: true])
        wordWrap = defaults.bool(forKey: Keys.wordWrap)
        previewAllowsScripts = defaults.bool(forKey: Keys.previewAllowsScripts)
        previewAllowsNetwork = defaults.bool(forKey: Keys.previewAllowsNetwork)

        let size = defaults.double(forKey: Keys.fontSize)
        if let name = defaults.string(forKey: Keys.fontName), size > 0,
           let saved = NSFont(name: name, size: size) {
            font = saved
        } else {
            font = Self.defaultFont
        }

        let savedShortcuts = defaults.dictionary(forKey: Keys.shortcuts) ?? [:]
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { action in
            let saved = (savedShortcuts[action.rawValue] as? [String: Any]).flatMap(Shortcut.init(stored:))
            return (action, saved ?? action.defaultShortcut)
        })

        if let saved = defaults.string(forKey: Keys.appearanceMode).flatMap(AppearanceMode.init(rawValue:)) {
            mode = saved
        } else {
            // Ohne gespeicherte Wahl: einmal nachsehen, ob der Mac hell oder dunkel ist.
            mode = defaults.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
        }
        let color = { (key: String, fallback: String) in
            defaults.string(forKey: key).flatMap { NSColor(hex: $0) } ?? NSColor(hex: fallback)!
        }
        let background = color(Keys.backgroundColor, "1E1E1E")
        backgroundColor = background
        menuColor = color(Keys.menuColor, background.hexString)
        textColor = color(Keys.textColor, "E6E6E6")
        barColor = color(Keys.barColor, "2D2D30")

        let saved = defaults.array(forKey: Keys.recentlyClosed) as? [[String: Any]] ?? []
        recentlyClosed = saved.compactMap { entry in
            guard let path = entry["path"] as? String, let time = entry["date"] as? Double else { return nil }
            return ClosedTab(url: URL(fileURLWithPath: path), date: Date(timeIntervalSince1970: time))
        }
    }

    // MARK: - Fenster

    /// Liefert den Zustand für ein gerade entstehendes Fenster: den eines
    /// herausgezogenen Tabs, falls einer wartet, sonst einen frischen.
    func claimStore() -> WindowStore {
        let store = pendingStores.isEmpty ? WindowStore() : pendingStores.removeFirst()
        windows.append(store)
        if !pendingURLs.isEmpty {
            // Erst nach dem Aufbau der Ansicht, die den Zustand gerade anfordert.
            DispatchQueue.main.async { self.open([]) }
        }
        return store
    }

    /// Öffnet vom Finder übergebene Dateien als Tabs im aktiven Fenster.
    func open(_ urls: [URL]) {
        pendingURLs += urls
        guard let store = activeStore ?? windows.last else {
            // Das neue Fenster holt sich die wartenden Dateien über `claimStore`.
            newWindow()
            return
        }
        let urls = pendingURLs
        pendingURLs = []
        urls.forEach(store.open)
        store.window?.makeKeyAndOrderFront(nil)
    }

    /// Fenster, die tatsächlich auf dem Bildschirm existieren.
    var liveWindows: [WindowStore] {
        windows.filter { $0.window != nil }
    }

    var activeStore: WindowStore? {
        let live = liveWindows
        return live.first { $0.window === NSApp.mainWindow }
            ?? live.first { $0.window === NSApp.keyWindow }
            ?? live.first
    }

    func newWindow() {
        openWindowAction?(id: Self.windowGroupID)
    }

    /// Öffnet ein neues Fenster, das nur den herausgezogenen Tab enthält.
    func openWindow(with document: TextDocument, near point: NSPoint) {
        let store = WindowStore(documents: [document])
        store.initialTopLeft = NSPoint(x: point.x - 160, y: point.y + 20)
        pendingStores.append(store)
        openWindowAction?(id: Self.windowGroupID)
    }

    func remove(_ store: WindowStore) {
        windows.removeAll { $0.id == store.id }
    }

    /// Sucht eine bereits geöffnete Datei in allen Fenstern.
    func locate(_ url: URL) -> (store: WindowStore, document: TextDocument)? {
        for store in liveWindows {
            if let document = store.documents.first(where: { $0.url == url }) {
                return (store, document)
            }
        }
        return nil
    }

    /// Fragt vor dem Beenden für jeden geänderten Tab nach. `false` bricht das Beenden ab.
    func confirmQuit() -> Bool {
        for store in liveWindows where !store.confirmCloseAll() {
            return false
        }
        return true
    }

    // MARK: - Zuletzt geschlossen

    func noteClosed(_ url: URL) {
        recentlyClosed.removeAll { $0.url == url }
        recentlyClosed.insert(ClosedTab(url: url, date: Date()), at: 0)
        recentlyClosed = Array(recentlyClosed.prefix(Self.recentlyClosedLimit))
        persistRecentlyClosed()
    }

    func noteOpened(_ url: URL) {
        guard recentlyClosed.contains(where: { $0.url == url }) else { return }
        recentlyClosed.removeAll { $0.url == url }
        persistRecentlyClosed()
    }

    func forgetClosed(_ url: URL) {
        noteOpened(url)
    }

    private func persistRecentlyClosed() {
        let entries = recentlyClosed.map { ["path": $0.url.path, "date": $0.date.timeIntervalSince1970] as [String: Any] }
        UserDefaults.standard.set(entries, forKey: Keys.recentlyClosed)
    }

    // MARK: - Tastenkürzel

    func shortcut(for action: ShortcutAction) -> Shortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) {
        shortcuts[action] = shortcut
        persistShortcuts()
        refreshMenuShortcuts()
    }

    /// SwiftUI trägt geänderte Kürzel erst in die Mac-Menüleiste ein, wenn ein
    /// Menü geöffnet wird; bis dahin würde noch die alte Kombination auslösen.
    /// Deshalb hier direkt in die Menüeinträge schreiben.
    private func refreshMenuShortcuts() {
        let items = (NSApp.mainMenu?.items ?? []).flatMap { $0.submenu?.items ?? [] }
        for action in ShortcutAction.allCases {
            guard let item = items.first(where: { $0.title == action.menuTitle }) else { continue }
            let shortcut = shortcut(for: action)
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
    }

    func resetShortcuts() {
        stopRecording()
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        shortcutMessage = nil
        UserDefaults.standard.removeObject(forKey: Keys.shortcuts)
        refreshMenuShortcuts()
    }

    /// Name des Befehls, der die Kombination schon belegt, sonst `nil`.
    func conflict(for shortcut: Shortcut, excluding action: ShortcutAction) -> String? {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && self.shortcut(for: $0) == shortcut }) {
            return other.title
        }
        return FixedShortcut.all.first { $0.shortcut == shortcut }?.title
    }

    private func persistShortcuts() {
        // Nur Abweichungen vom Standard speichern.
        let changed = shortcuts.filter { $0.value != $0.key.defaultShortcut }
        let stored = Dictionary(uniqueKeysWithValues: changed.map { ($0.key.rawValue, $0.value.stored) })
        UserDefaults.standard.set(stored, forKey: Keys.shortcuts)
    }

    /// Nimmt den nächsten Tastendruck als neues Kürzel für `action` auf.
    func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        shortcutMessage = nil
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            // Der Tastendruck gehört der Aufnahme und löst sonst nichts aus.
            return nil
        }
    }

    func stopRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        recordingAction = nil
    }

    private func record(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        let escapeKeyCode: UInt16 = 53
        if event.keyCode == escapeKeyCode {
            stopRecording()
            return
        }
        guard let shortcut = Shortcut(event: event) else { return }
        guard shortcut.isUsable else {
            shortcutMessage = String(localized: "Also press ⌘, ⌃, or ⌥.")
            return
        }
        if let other = conflict(for: shortcut, excluding: action) {
            shortcutMessage = String(localized: "\(shortcut.display) is already assigned to “\(other)”.")
            return
        }
        setShortcut(shortcut, for: action)
        shortcutMessage = nil
        stopRecording()
    }

    // MARK: - Farben

    /// Feste Farben des aktuellen Modus. `nil` bei Hell und Dunkel, dort
    /// gelten die Standardfarben des Macs für das jeweilige Erscheinungsbild.
    var palette: Palette? {
        switch mode {
        case .light, .dark: nil
        case .windows: .windows
        case .custom: Palette(bar: barColor, menu: menuColor, background: backgroundColor, text: textColor)
        }
    }

    var editorBackground: NSColor {
        palette?.background ?? .textBackgroundColor
    }

    var editorText: NSColor {
        palette?.text ?? .textColor
    }

    /// Farben und Schrift des Editors als CSS-Variablen für `Preview/preview.css`.
    var previewThemeCSS: String {
        resolved {
            let palette = SyntaxPalette(background: editorBackground, text: editorText)
            let isDark = editorBackground.matchingScheme == .dark
            let family = (displayFont.familyName ?? "").replacingOccurrences(of: "\"", with: "")
            var values = [
                "--bg: #\(editorBackground.hexString)",
                "--text: #\(editorText.hexString)",
                "--font: \"\(family)\"",
                "--size: \(Int(displayFont.pointSize))px",
                "--dark: \(isDark ? 1 : 0)",
                "color-scheme: \(isDark ? "dark" : "light")",
            ]
            for token in SyntaxToken.allCases {
                values.append("--\(token): #\(palette.color(for: token).hexString)")
            }
            return ":root { " + values.joined(separator: "; ") + "; }"
        }
    }

    /// Hell und Dunkel nutzen Systemfarben, die erst das Erscheinungsbild auflöst.
    private func resolved<Value>(_ make: () -> Value) -> Value {
        var value = make()
        NSApplication.shared.appearance?.performAsCurrentDrawingAppearance { value = make() }
        return value
    }

    /// Farbe der Menüzeile und des ausgewählten Tabs, der in sie übergeht.
    var menuBackground: NSColor {
        palette?.menu ?? .textBackgroundColor
    }

    /// Hell/Dunkel für Menüzeile und Tab-Leiste, damit deren Schrift auf einer
    /// festen Farbe lesbar bleibt. `nil`: nichts erzwingen.
    var menuScheme: ColorScheme? {
        palette?.menu.matchingScheme
    }

    var barScheme: ColorScheme? {
        palette?.bar.matchingScheme
    }

    func setMode(_ newMode: AppearanceMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Keys.appearanceMode)
        applyAppearance()
    }

    func setBackgroundColor(_ color: NSColor) {
        backgroundColor = color
        persistColors()
        applyAppearance()
    }

    func setMenuColor(_ color: NSColor) {
        menuColor = color
        persistColors()
    }

    func setTextColor(_ color: NSColor) {
        textColor = color
        persistColors()
    }

    func setBarColor(_ color: NSColor) {
        barColor = color
        persistColors()
    }

    /// Stellt die ganze App hell oder dunkel, passend zum gewählten Modus.
    func applyAppearance() {
        let name: NSAppearance.Name = switch mode {
        case .light: .aqua
        case .dark: .darkAqua
        case .windows, .custom: editorBackground.matchingScheme == .dark ? .darkAqua : .aqua
        }
        NSApplication.shared.appearance = NSAppearance(named: name)
    }

    private func persistColors() {
        let defaults = UserDefaults.standard
        defaults.set(backgroundColor.hexString, forKey: Keys.backgroundColor)
        defaults.set(menuColor.hexString, forKey: Keys.menuColor)
        defaults.set(textColor.hexString, forKey: Keys.textColor)
        defaults.set(barColor.hexString, forKey: Keys.barColor)
    }

    // MARK: - Format und Ansicht

    /// Schrift inklusive Zoom, so wie sie in der Textfläche erscheint.
    var displayFont: NSFont {
        NSFontManager.shared.convert(font, toSize: (font.pointSize * zoom).rounded())
    }

    func setWordWrap(_ enabled: Bool) {
        wordWrap = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.wordWrap)
    }

    func setPreviewAllowsScripts(_ enabled: Bool) {
        previewAllowsScripts = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.previewAllowsScripts)
    }

    func setPreviewAllowsNetwork(_ enabled: Bool) {
        previewAllowsNetwork = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.previewAllowsNetwork)
    }

    func setFont(_ newFont: NSFont) {
        font = newFont
        UserDefaults.standard.set(newFont.fontName, forKey: Keys.fontName)
        UserDefaults.standard.set(Double(newFont.pointSize), forKey: Keys.fontSize)
    }

    func setFontFamily(_ family: String) {
        guard let newFont = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: font.pointSize) else { return }
        setFont(newFont)
    }

    func setFontSize(_ size: CGFloat) {
        setFont(NSFontManager.shared.convert(font, toSize: size))
    }

    func zoomIn() { zoom = min(zoom + 0.1, 5) }
    func zoomOut() { zoom = max(zoom - 0.1, 0.5) }
    func resetZoom() { zoom = 1 }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.runModal()
    }
}
