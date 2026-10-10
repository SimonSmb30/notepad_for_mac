import SwiftUI

/// Einstellungen (⌘,): Darstellung, Text, Vorschau und eine Übersicht der Tastenkürzel.
struct SettingsView: View {
    @Environment(Workspace.self) private var workspace

    /// Eine Zeile der Kürzel-Liste: änderbar oder von macOS vorgegeben.
    private enum ShortcutRow: Identifiable {
        case action(ShortcutAction)
        case fixed(FixedShortcut)

        var id: String {
            switch self {
            case .action(let action): action.rawValue
            case .fixed(let fixed): "fixed-" + fixed.id
            }
        }
    }

    private static let shortcutRows: [ShortcutRow] =
        ShortcutAction.allCases.map(ShortcutRow.action)
        + FixedShortcut.all.filter(\.isListed).map(ShortcutRow.fixed)

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    /// Übliche Größen, ergänzt um die aktuelle, falls sie nicht dabei ist.
    private var fontSizes: [Int] {
        let current = Int(workspace.font.pointSize.rounded())
        return Array(Set([9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72] + [current])).sorted()
    }

    @State private var contentHeight: CGFloat = 600

    /// So hoch darf das Fenster höchstens werden, damit es auf den Bildschirm passt.
    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 80
    }

    var body: some View {
        // Passt der Inhalt nicht auf den Bildschirm, wird gescrollt.
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(width: 500, height: min(contentHeight, maxHeight))
        .onDisappear { workspace.stopRecording() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Appearance") {
                row("Mode") {
                    Picker("Mode", selection: Binding(
                        get: { workspace.mode },
                        set: { workspace.setMode($0) }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                if workspace.mode == .custom {
                    Divider()
                    colorRow("Tab Bar", \.barColor, set: workspace.setBarColor)
                    colorRow("Menu Bar", \.menuColor, set: workspace.setMenuColor)
                    colorRow("Text Area", \.backgroundColor, set: workspace.setBackgroundColor)
                    colorRow("Text Color", \.textColor, set: workspace.setTextColor)
                }
            }

            section("Text") {
                row("Font") {
                    FontFamilyPicker(
                        families: Self.fontFamilies,
                        selection: workspace.font.familyName ?? "",
                        onSelect: { workspace.setFontFamily($0) }
                    )
                    .frame(width: 240)
                }
                row("Font Size") {
                    Picker("Font Size", selection: Binding(
                        get: { Int(workspace.font.pointSize.rounded()) },
                        set: { workspace.setFontSize(CGFloat($0)) }
                    )) {
                        ForEach(fontSizes, id: \.self) { size in
                            Text("\(size) pt").tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Divider()
                row("Word Wrap") {
                    Toggle("Word Wrap", isOn: Binding(
                        get: { workspace.wordWrap },
                        set: { workspace.setWordWrap($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            section("Preview") {
                row("Run Scripts in HTML Files") {
                    Toggle("Run Scripts in HTML Files", isOn: Binding(
                        get: { workspace.previewAllowsScripts },
                        set: { workspace.setPreviewAllowsScripts($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                row("Load Content from the Internet") {
                    Toggle("Load Content from the Internet", isOn: Binding(
                        get: { workspace.previewAllowsNetwork },
                        set: { workspace.setPreviewAllowsNetwork($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            section("Keyboard Shortcuts") {
                // Zwei Spalten, von oben nach unten gelesen.
                let half = (Self.shortcutRows.count + 1) / 2
                HStack(alignment: .top, spacing: 28) {
                    shortcutColumn(Self.shortcutRows.prefix(half))
                    shortcutColumn(Self.shortcutRows.dropFirst(half))
                }
                Divider()
                VStack(spacing: 8) {
                    // Nur bei einer abgelehnten Kombination, etwa weil sie schon vergeben ist.
                    if let message = workspace.shortcutMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    Button("Restore Defaults") { workspace.resetShortcuts() }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private func shortcutColumn(_ rows: ArraySlice<ShortcutRow>) -> some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                HStack {
                    switch row {
                    case .action(let action):
                        Text(action.title)
                        Spacer()
                        shortcutButton(action)
                    case .fixed(let fixed):
                        Text(fixed.title)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(fixed.shortcut.display, systemImage: "lock.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .help("Set by macOS")
                    }
                }
                .frame(height: 22)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
    }

    private func shortcutButton(_ action: ShortcutAction) -> some View {
        let isRecording = workspace.recordingAction == action
        return Button {
            if isRecording {
                workspace.stopRecording()
            } else {
                workspace.startRecording(action)
            }
        } label: {
            Text(isRecording ? String(localized: "Press Shortcut…") : workspace.shortcut(for: action).display)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 20)
                .background(
                    isRecording ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change Shortcut")
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Beschriftung links, Bedienelement rechts.
    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    private func colorRow(_ title: LocalizedStringKey, _ keyPath: KeyPath<Workspace, NSColor>, set: @escaping (NSColor) -> Void) -> some View {
        row(title) {
            ColorPicker(title, selection: Binding(
                get: { Color(nsColor: workspace[keyPath: keyPath]) },
                set: { set(NSColor($0)) }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}
