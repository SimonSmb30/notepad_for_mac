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
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
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
