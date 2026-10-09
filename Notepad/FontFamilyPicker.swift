import AppKit
import SwiftUI

/// Auswahlfeld für die Schriftart, in dem jeder Eintrag in seiner eigenen
/// Schrift erscheint. SwiftUI-Menüs zeigen Einträge nur in der Systemschrift,
/// deshalb ein `NSPopUpButton`.
struct FontFamilyPicker: NSViewRepresentable {
    let families: [String]
    let selection: String
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for family in families {
            let item = NSMenuItem(title: family, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: family, attributes: [.font: Self.previewFont(for: family)])
            button.menu?.addItem(item)
        }
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        if button.titleOfSelectedItem != selection {
            button.selectItem(withTitle: selection)
        }
    }

    /// Die Schrift selbst, sofern sie ihren eigenen Namen darstellen kann.
    /// Symbolschriften wie Webdings würden sonst nur Zeichensalat zeigen.
    private static func previewFont(for family: String) -> NSFont {
        let size = NSFont.systemFontSize
        guard let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size),
              CharacterSet(charactersIn: family).isSubset(of: font.coveredCharacterSet) else {
            return .systemFont(ofSize: size)
        }
        return font
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (String) -> Void

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            if let family = sender.titleOfSelectedItem {
                onSelect(family)
            }
        }
    }
}
