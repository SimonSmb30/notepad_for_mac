import SwiftUI

/// Die Menüzeile im Fenster, direkt unter den Tabs.
struct MenuRowView: View {
    @Environment(WindowStore.self) private var windowStore
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let store: () -> WindowStore? = { windowStore }
        let shortcuts = workspace.shortcuts
        HStack(spacing: 0) {
            menu("File") {
                FileOpenItems(store: store, shortcuts: shortcuts)
                FileSaveItems(store: store, shortcuts: shortcuts)
            }
            SettingsLink {
                Text("Settings")
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if let document = windowStore.current, document.availableModes.count > 1 {
                PreviewSwitch(document: document)
            }
        }
        // Links beginnt „Datei“ auf derselben Linie wie der Text darunter (Einzug 8 + 1),
        // rechts hat der Knopf denselben Abstand wie nach oben und unten.
        .padding(.leading, 1)
        .padding(.trailing, PreviewSwitch.margin)
        .frame(height: PreviewSwitch.side + 2 * PreviewSwitch.margin)
        .background(Color(nsColor: workspace.menuBackground))
    }

    private func menu<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        // Schlichter Stil, damit „Datei“ genauso aussieht wie „Einstellungen“ daneben.
        Menu(title, content: content)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 8)
    }
}

/// Wechselt zwischen Text und Vorschau. Das Symbol zeigt die aktuelle Ansicht.
private struct PreviewSwitch: View {
    let document: TextDocument
    @State private var isHovered = false

    static let side: CGFloat = 24
    static let margin: CGFloat = 4

    var body: some View {
        let mode = document.effectiveMode
        Button {
            document.cycleViewMode()
        } label: {
            Image(systemName: mode.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: Self.side, height: Self.side)
                .background(Color.primary.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(mode.title)
        .accessibilityLabel(mode.title)
    }
}
