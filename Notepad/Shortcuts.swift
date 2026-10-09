import AppKit
import SwiftUI

/// Die Befehle, deren Tastenkürzel sich in den Einstellungen ändern lassen.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case newTab, newWindow, open, save, saveAs, print, closeTab, tabSearch
    case find, replace, goToLine, timestamp, zoomIn, zoomOut, resetZoom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: String(localized: "New Tab")
        case .newWindow: String(localized: "New Window")
        case .open: String(localized: "Open")
        case .save: String(localized: "Save")
        case .saveAs: String(localized: "Save As")
        case .print: String(localized: "Print")
        case .closeTab: String(localized: "Close Tab")
        case .tabSearch: String(localized: "Search Tabs")
        case .find: String(localized: "Find")
        case .replace: String(localized: "Replace")
        case .goToLine: String(localized: "Go to Line")
        case .timestamp: String(localized: "Time/Date")
        case .zoomIn: String(localized: "Zoom In")
        case .zoomOut: String(localized: "Zoom Out")
        case .resetZoom: String(localized: "Actual Size")
        }
    }

    /// Beschriftung des Menüeintrags; über sie wird der Eintrag in der
    /// Mac-Menüleiste wiedergefunden.
    var menuTitle: String {
        switch self {
        // Die Auslassungspunkte stehen je nach Sprache mit oder ohne Leerzeichen.
        case .open, .saveAs, .print, .tabSearch, .find, .replace, .goToLine: String(localized: "\(title)…")
        default: title
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .newTab: Shortcut("n", .command)
        case .newWindow: Shortcut("n", [.command, .shift])
        case .open: Shortcut("o", .command)
        case .save: Shortcut("s", .command)
        case .saveAs: Shortcut("s", [.command, .shift])
        case .print: Shortcut("p", .command)
        case .closeTab: Shortcut("w", .command)
        case .tabSearch: Shortcut("a", [.command, .shift])
        case .find: Shortcut("f", .command)
        case .replace: Shortcut("f", [.command, .option])
        case .goToLine: Shortcut("l", .command)
        case .timestamp: Shortcut(Shortcut.functionKey(5), [])
        case .zoomIn: Shortcut("+", .command)
        case .zoomOut: Shortcut("-", .command)
        case .resetZoom: Shortcut("0", .command)
        }
    }
}

/// Eine Tastenkombination: die Taste ohne Umschalttaste plus Zusatztasten.
struct Shortcut: Equatable {
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    let key: String
    let modifiers: NSEvent.ModifierFlags

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// Liest die Kombination aus einem Tastendruck. `nil`, wenn keine Taste erkennbar ist.
    init?(event: NSEvent) {
        // Die Taste ohne Zusatztasten, damit ⇧⌘7 als „7“ und nicht als „/“ gilt.
        guard let key = event.characters(byApplyingModifiers: [])?.lowercased(), !key.isEmpty else { return nil }
        self.init(key, event.modifierFlags)
    }

    static func functionKey(_ number: Int) -> String {
        String(UnicodeScalar(NSF1FunctionKey + number - 1)!)
    }

    private var functionKeyNumber: Int? {
        guard let scalar = key.unicodeScalars.first else { return nil }
        let number = Int(scalar.value) - NSF1FunctionKey + 1
        return (1...20).contains(number) ? number : nil
    }

    /// Ohne ⌘, ⌃ oder ⌥ würde die Kombination normales Tippen abfangen.
    var isUsable: Bool {
        functionKeyNumber != nil || !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyName
    }

    private var keyName: String {
        if let functionKeyNumber { return "F\(functionKeyNumber)" }
        switch key {
        case " ": return String(localized: "Space")
        case "\r": return "↩"
        case "\t": return "⇥"
        case "\u{7F}", "\u{8}": return "⌫"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): return "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): return "↓"
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): return "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): return "→"
        case "-": return "−"
        default: return key.uppercased()
        }
    }

    var keyboardShortcut: KeyboardShortcut {
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: eventModifiers)
    }

    // MARK: - Speichern

    var stored: [String: Any] {
        ["key": key, "modifiers": Int(modifiers.rawValue)]
    }

    init?(stored: [String: Any]) {
        guard let key = stored["key"] as? String, key.count == 1, let raw = stored["modifiers"] as? Int else { return nil }
        self.init(key, NSEvent.ModifierFlags(rawValue: UInt(raw)))
    }
}

/// Kürzel, die macOS vorgibt und die sich hier nicht ändern lassen.
struct FixedShortcut: Identifiable {
    let title: String
    let shortcut: Shortcut
    /// `false`: nur für die Konfliktprüfung, nicht in der Liste gezeigt.
    var isListed = true

    var id: String { title }

    static let all: [FixedShortcut] = [
        FixedShortcut(title: String(localized: "Settings"), shortcut: Shortcut(",", .command)),
        FixedShortcut(title: String(localized: "Quit"), shortcut: Shortcut("q", .command)),
        FixedShortcut(title: String(localized: "Undo"), shortcut: Shortcut("z", .command)),
        FixedShortcut(title: String(localized: "Redo"), shortcut: Shortcut("z", [.command, .shift])),
        FixedShortcut(title: String(localized: "Cut"), shortcut: Shortcut("x", .command)),
        FixedShortcut(title: String(localized: "Copy"), shortcut: Shortcut("c", .command)),
        FixedShortcut(title: String(localized: "Paste"), shortcut: Shortcut("v", .command)),
        FixedShortcut(title: String(localized: "Select All"), shortcut: Shortcut("a", .command)),
        FixedShortcut(title: String(localized: "Hide"), shortcut: Shortcut("h", .command), isListed: false),
        FixedShortcut(title: String(localized: "Minimize"), shortcut: Shortcut("m", .command), isListed: false),
    ]
}

extension View {
    /// Hängt das Kürzel des Befehls aus der übergebenen Belegung an.
    func shortcut(_ action: ShortcutAction, _ shortcuts: [ShortcutAction: Shortcut]) -> some View {
        keyboardShortcut((shortcuts[action] ?? action.defaultShortcut).keyboardShortcut)
    }
}
