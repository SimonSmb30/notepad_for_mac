import SwiftUI

/// Die Tab-Suche hinter dem Pfeil in der Tab-Leiste: alle offenen Tabs aller
/// Fenster und die zuletzt geschlossenen Dateien.
struct TabSearchView: View {
    let store: WindowStore
    /// Höchstens so hoch darf die Liste werden, damit sie ins Fenster passt.
    var maxListHeight: CGFloat = 440

    @Environment(Workspace.self) private var workspace
    @State private var query = ""
    @State private var showsClosed = true
    @FocusState private var isSearchFocused: Bool

    private struct OpenEntry: Identifiable {
        let store: WindowStore
        let document: TextDocument
        var id: TextDocument.ID { document.id }
    }

    private let rowHeight: CGFloat = 46
    private let headerHeight: CGFloat = 34

    var body: some View {
        let open = openEntries
        let closed = closedEntries

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Tabs", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { activateFirstMatch(open: open, closed: closed) }
                Text(verbatim: workspace.shortcut(for: .tabSearch).display)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header("Open Tabs")
                    if open.isEmpty {
                        Text("No Results")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .frame(height: rowHeight)
                    }
                    ForEach(open) { entry in
                        TabSearchRow(
                            icon: entry.document.isDirty ? "doc.badge.ellipsis" : "doc.text",
                            title: entry.document.title,
                            subtitle: subtitle(for: entry.document),
                            onSelect: {
                                dismiss()
                                entry.store.focus(entry.document)
                            },
                            onClose: { entry.store.close(entry.document) }
                        )
                        .frame(height: rowHeight)
                    }

                    if !closed.isEmpty {
                        Button {
                            showsClosed.toggle()
                        } label: {
                            HStack {
                                Text("Recently Closed")
                                Spacer()
                                Image(systemName: showsClosed ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .frame(height: headerHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showsClosed {
                            ForEach(closed) { entry in
                                TabSearchRow(
                                    icon: "clock.arrow.circlepath",
                                    title: entry.url.lastPathComponent,
                                    subtitle: "\(folder(of: entry.url)) • \(relativeTime(entry.date))",
                                    onSelect: {
                                        dismiss()
                                        store.open(entry.url)
                                    },
                                    closeHelp: String(localized: "Remove from List"),
                                    onClose: { workspace.forgetClosed(entry.url) }
                                )
                                .frame(height: rowHeight)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(height: listHeight(open: open.count, closed: closed.count))
        }
        .frame(width: 320)
        .onAppear { isSearchFocused = true }
        .onExitCommand { dismiss() }
    }

    // MARK: - Inhalte

    private var openEntries: [OpenEntry] {
        // Das eigene Fenster zuerst, dann die übrigen.
        let windows = [store] + workspace.liveWindows.filter { $0.id != store.id }
        return windows
            .flatMap { window in window.documents.map { OpenEntry(store: window, document: $0) } }
            .filter { matches($0.document.title) || matches($0.document.url?.path ?? "") }
    }

    private var closedEntries: [ClosedTab] {
        workspace.recentlyClosed.filter { matches($0.url.path) }
    }

    private func matches(_ text: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || text.localizedCaseInsensitiveContains(needle)
    }

    private func subtitle(for document: TextDocument) -> String {
        guard let url = document.url else {
            return document.isDirty ? String(localized: "Unsaved • Edited") : String(localized: "Unsaved")
        }
        return document.isDirty ? String(localized: "\(folder(of: url)) • Edited") : folder(of: url)
    }

    private func folder(of url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        // Die Sprache der App, nicht die Region des Macs: sonst stünde eine
        // deutsche Zeitangabe zwischen englischen Texten oder umgekehrt.
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.unitsStyle = .short
        // Eine gerade eben geschlossene Datei soll nicht als „in 0 Sek.“ erscheinen.
        return formatter.localizedString(for: min(date, Date().addingTimeInterval(-1)), relativeTo: Date())
    }

    private func listHeight(open: Int, closed: Int) -> CGFloat {
        var height = headerHeight + CGFloat(max(open, 1)) * rowHeight + 6
        if closed > 0 {
            height += headerHeight + (showsClosed ? CGFloat(closed) * rowHeight : 0)
        }
        return min(height, maxListHeight)
    }

    // MARK: - Aktionen

    private func activateFirstMatch(open: [OpenEntry], closed: [ClosedTab]) {
        if let first = open.first {
            dismiss()
            first.store.focus(first.document)
        } else if let first = closed.first {
            dismiss()
            store.open(first.url)
        }
    }

    private func dismiss() {
        store.isTabSearchPresented = false
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: headerHeight)
    }
}

private struct TabSearchRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let onSelect: () -> Void
    var closeHelp = String(localized: "Close Tab")
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(isCloseHovered ? 0.18 : 0), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovered = $0 }
                .help(closeHelp)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(
            isHovered ? Color.primary.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}
