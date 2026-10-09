import SwiftUI

/// Tabs in der Titelleiste, rechts neben den drei Fensterpunkten.
struct TabBarView: View {
    @Environment(WindowStore.self) private var store
    @Environment(Workspace.self) private var workspace

    @State private var hoveredID: TextDocument.ID?

    private let chevronWidth: CGFloat = 24
    private let plusWidth: CGFloat = 28
    /// Breite des Plus-Symbols in seiner Klickfläche, für den Abstand zum rechten Rand.
    private let plusGlyphWidth: CGFloat = 12
    private let tabsLeading: CGFloat = 8
    private let maxTabWidth: CGFloat = 170
    private let minTabWidth: CGFloat = 44

    var body: some View {
        @Bindable var store = store
        GeometryReader { geometry in
            let documents = store.documents
            let tabWidth = tabWidth(in: geometry.size.width, count: documents.count)
            HStack(alignment: .center, spacing: 0) {
                Button {
                    store.isTabSearchPresented.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: chevronWidth, height: 24)
                        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tab Search")
                .padding(.trailing, tabsLeading)

                ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                    TabItemView(
                        document: document,
                        width: tabWidth,
                        selectedFill: Color(nsColor: workspace.menuBackground),
                        selectedScheme: workspace.menuScheme,
                        isSelected: document.id == store.selectedID,
                        isHovered: document.id == hoveredID,
                        showsSeparator: showsSeparator(after: index, in: documents),
                        canDetach: documents.count > 1,
                        onSelect: { store.selectedID = document.id },
                        onClose: { store.close(document) },
                        onDetach: { store.detach(document) },
                        onHover: { inside in
                            if inside {
                                hoveredID = document.id
                            } else if hoveredID == document.id {
                                hoveredID = nil
                            }
                        }
                    )
                }

                Button(action: store.newDocument) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: plusWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab")

                // Die freie Fläche verschiebt das Fenster, wie eine normale Titelleiste.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
            }
            .padding(.leading, WindowStore.windowButtonsWidth)
            .padding(.trailing, trailingPadding)
            .frame(width: geometry.size.width, height: WindowStore.tabBarHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: WindowStore.tabBarHeight)
        .background { barBackground }
        .overlay(alignment: .leading) {
            if store.isFullScreen {
                FullScreenWindowButtons(
                    size: store.windowButtonSize,
                    spacing: store.windowButtonSpacing,
                    onClose: store.closeWindow,
                    onExitFullScreen: store.toggleFullScreen
                )
                .padding(.leading, store.windowButtonMargin)
            }
        }
    }
}

/// Die drei Fensterpunkte im Vollbild, wo AppKit die echten ausblendet.
private struct FullScreenWindowButtons: View {
    let size: CGSize
    /// Abstand von der linken Kante eines Punkts zur linken Kante des nächsten.
    let spacing: CGFloat
    let onClose: () -> Void
    let onExitFullScreen: () -> Void

    @State private var isHovered = false

    private let diameter: CGFloat = 12

    var body: some View {
        HStack(spacing: max(0, spacing - size.width)) {
            dot(Color(red: 1, green: 0.37, blue: 0.34), symbol: "xmark", help: String(localized: "Close"), action: onClose)
            // Im Vollbild lässt sich ein Fenster nicht minimieren.
            dot(Color.primary.opacity(0.2), symbol: nil, help: "", action: nil)
            dot(Color(red: 0.16, green: 0.78, blue: 0.25), symbol: "arrow.down.right.and.arrow.up.left",
                help: String(localized: "Exit Full Screen"), action: onExitFullScreen)
        }
        .onHover { isHovered = $0 }
    }

    private func dot(_ color: Color, symbol: String?, help: String, action: (() -> Void)?) -> some View {
        Button(action: action ?? {}) {
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .overlay {
                    if isHovered, let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .help(help)
    }
}

private extension TabBarView {
    /// Am Anschlag steht das Plus so weit vom rechten Rand wie der rote Punkt vom linken.
    var trailingPadding: CGFloat {
        max(0, store.windowButtonMargin - (plusWidth - plusGlyphWidth) / 2)
    }

    /// Tabs behalten ihre volle Breite, bis das Plus am rechten Rand anschlägt;
    /// erst dann teilen sie sich den vorhandenen Platz.
    func tabWidth(in barWidth: CGFloat, count: Int) -> CGFloat {
        let fixed = WindowStore.windowButtonsWidth + chevronWidth + tabsLeading + plusWidth + trailingPadding
        let available = (barWidth - fixed) / CGFloat(max(count, 1))
        return min(maxTabWidth, max(minTabWidth, available.rounded(.down)))
    }

    /// Ein Trennstrich steht nur zwischen zwei ruhenden Tabs.
    func showsSeparator(after index: Int, in documents: [TextDocument]) -> Bool {
        guard index + 1 < documents.count else { return false }
        return [documents[index].id, documents[index + 1].id]
            .allSatisfy { $0 != store.selectedID && $0 != hoveredID }
    }
}

private extension TabBarView {
    var barBackground: Color {
        workspace.palette.map { Color(nsColor: $0.bar) } ?? Color.primary.opacity(0.08)
    }
}

private struct TabItemView: View {
    let document: TextDocument
    let width: CGFloat
    let selectedFill: Color
    /// Hell/Dunkel für die Schrift des ausgewählten Tabs, passend zu `selectedFill`.
    let selectedScheme: ColorScheme?
    let isSelected: Bool
    let isHovered: Bool
    let showsSeparator: Bool
    let canDetach: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDetach: () -> Void
    let onHover: (Bool) -> Void

    @State private var dragOffset: CGSize = .zero

    /// So weit muss ein Tab nach oben oder unten gezogen werden, um sich zu lösen.
    private let detachDistance: CGFloat = 36

    var body: some View {
        Group {
            if isSelected {
                HStack(spacing: 6) {
                    clippedTitle
                    closeButton
                }
            } else {
                // Wie in Chrome: Bevor der Titel abgeschnitten wird, weicht das
                // Schließen-Kreuz; nur der ausgewählte Tab behält es immer.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(document.title)
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 0)
                        closeButton
                    }
                    clippedTitle
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(isSelected ? .primary : .secondary)
        .localColorScheme(isSelected ? selectedScheme : nil)
        .padding(.horizontal, 10)
        .frame(width: width)
        // Der Inhalt sitzt mittig in der ganzen Leiste; die Tab-Form beginnt
        // etwas tiefer und reicht bis an deren Unterkante.
        .frame(height: WindowStore.tabBarHeight)
        .background {
            if isSelected {
                SelectedTabShape(radius: 8)
                    .fill(selectedFill)
                    .padding(.top, 6)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
                    .padding(.vertical, 6)
            }
        }
        .overlay(alignment: .trailing) {
            if showsSeparator {
                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 1, height: 16)
                    .offset(x: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
        .offset(dragOffset)
        .opacity(isDetaching ? 0.6 : 1)
        .zIndex(dragOffset != .zero ? 2 : (isSelected ? 1 : 0))
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    guard canDetach else { return }
                    if dragOffset == .zero { onSelect() }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let shouldDetach = canDetach && abs(value.translation.height) > detachDistance
                    dragOffset = .zero
                    if shouldDetach { onDetach() }
                }
        )
    }

    /// Zu lange Titel werden rechts hart abgeschnitten, ohne Auslassungspunkte.
    private var clippedTitle: some View {
        Text(document.title)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close Tab")
    }

    private var isDetaching: Bool {
        abs(dragOffset.height) > detachDistance
    }
}

/// Tab-Umriss wie in Chrome: oben abgerundet, unten läuft er mit einer
/// Gegenrundung nach außen in die Leiste darunter aus.
private struct SelectedTabShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - radius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX + radius, y: rect.maxY), radius: radius)
        path.closeSubpath()
        return path
    }
}
