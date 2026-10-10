import AppKit
import SwiftUI

/// Verbindet ein Fenster der Fenstergruppe mit seinem Zustand.
struct WindowRootView: View {
    @State private var holder = StoreHolder()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let workspace = Workspace.shared
        ContentView()
            .environment(holder.store)
            .environment(workspace)
            .onAppear {
                workspace.openWindowAction = openWindow
                workspace.applyAppearance()
            }
    }

    /// Holt den Zustand erst beim ersten Zugriff, also genau einmal pro Fenster.
    @MainActor
    private final class StoreHolder {
        lazy var store = Workspace.shared.claimStore()
    }
}

struct ContentView: View {
    @Environment(WindowStore.self) private var store
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
                .localColorScheme(workspace.barScheme)
            MenuRowView()
                .localColorScheme(workspace.menuScheme)
            Divider()
            // Jeder Tab behält seine eigene Textansicht, damit Rückgängig-Verlauf
            // und Scrollposition beim Wechseln erhalten bleiben.
            let previewTheme = workspace.previewThemeCSS
            ZStack {
                ForEach(store.documents) { document in
                    let isSelected = document.id == store.selectedID
                    let mode = document.effectiveMode
                    EditorTextView(
                        document: document,
                        displayFont: workspace.displayFont,
                        wordWrap: workspace.wordWrap,
                        backgroundColor: workspace.editorBackground,
                        textColor: workspace.editorText,
                        isSelected: isSelected,
                        isInteractive: !store.isTabSearchPresented && mode != .rendered
                    )
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .zIndex(isSelected ? 1 : 0)
                    // Die Vorschau entsteht beim Umschalten und zeigt den Text von diesem Moment.
                    if mode == .rendered, let kind = document.previewKind, let url = document.url {
                        PreviewView(content: PreviewSchemeHandler.Content(
                            documentURL: url,
                            kind: kind,
                            text: document.text,
                            themeCSS: previewTheme,
                            allowsScripts: workspace.previewAllowsScripts,
                            allowsNetwork: workspace.previewAllowsNetwork
                        ))
                        .background(Color(nsColor: workspace.editorBackground))
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .zIndex(isSelected ? 2 : 0)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if store.isTabSearchPresented {
                tabSearchDropdown
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 420, minHeight: 260)
        .background(WindowAccessor { store.attach($0) })
        .navigationTitle(store.current?.title ?? "Notepad")
    }
}

private extension ContentView {
    /// Die Tab-Suche als Aufklappfeld, links bündig mit dem Pfeil-Knopf.
    var tabSearchDropdown: some View {
        GeometryReader { geometry in
            let top = WindowStore.tabBarHeight - 4
            ZStack(alignment: .topLeading) {
                // Ein Klick daneben schließt das Feld.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { store.isTabSearchPresented = false }

                TabSearchView(store: store, maxListHeight: max(120, geometry.size.height - top - 70))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                    .padding(.leading, WindowStore.windowButtonsWidth)
                    .padding(.top, top)
            }
        }
    }
}

/// Reicht das `NSWindow` hinter der SwiftUI-Ansicht nach außen.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
