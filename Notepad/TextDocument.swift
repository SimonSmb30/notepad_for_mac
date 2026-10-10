import AppKit
import Observation

/// Wie ein Tab seinen Inhalt zeigt.
enum ViewMode {
    case raw, rendered

    var title: String {
        switch self {
        case .raw: String(localized: "Text")
        case .rendered: String(localized: "Preview")
        }
    }

    var symbol: String {
        switch self {
        case .raw: "chevron.left.forwardslash.chevron.right"
        case .rendered: "eye.fill"
        }
    }
}

/// Ein Tab: eine Textdatei oder ein noch ungespeichertes „Unbenannt“.
@MainActor
@Observable
final class TextDocument: Identifiable {
    let id = UUID()
    var url: URL?
    var text: String
    var isDirty = false
    /// Der Schalter in der Menüzeile.
    var viewMode = ViewMode.raw

    /// Die Textansicht dieses Tabs, damit Menübefehle sie direkt ansprechen können.
    @ObservationIgnored weak var textView: NSTextView?

    init(url: URL? = nil, text: String = "") {
        self.url = url
        self.text = text
    }

    var title: String {
        url?.lastPathComponent ?? String(localized: "Untitled")
    }

    /// Wie die Vorschau die Datei darstellt; `nil`, wenn es für sie keine gibt.
    var previewKind: PreviewKind? {
        url.flatMap(PreviewKind.init)
    }

    /// Die Ansichten, die es für diese Datei gibt.
    var availableModes: [ViewMode] {
previewKind == nil ? [.raw] : [.raw, .rendered]
    }

    /// Nach „Sichern unter“ mit anderer Endung kann der Schalter noch auf einer
    /// Ansicht stehen, die es für die Datei nicht mehr gibt.
    var effectiveMode: ViewMode {
        availableModes.contains(viewMode) ? viewMode : .raw
    }

    func cycleViewMode() {
        let modes = availableModes
        viewMode = modes[((modes.firstIndex(of: effectiveMode) ?? 0) + 1) % modes.count]
    }

    /// Ein frischer, leerer Tab darf beim Öffnen einer Datei ersetzt werden.
    var isPristine: Bool {
        url == nil && !isDirty && text.isEmpty
    }
}
