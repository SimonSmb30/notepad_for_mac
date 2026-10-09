import AppKit
import Observation

/// Ein Tab: eine Textdatei oder ein noch ungespeichertes „Unbenannt“.
@MainActor
@Observable
final class TextDocument: Identifiable {
    let id = UUID()
    var url: URL?
    var text: String
    var isDirty = false

    /// Die Textansicht dieses Tabs, damit Menübefehle sie direkt ansprechen können.
    @ObservationIgnored weak var textView: NSTextView?

    init(url: URL? = nil, text: String = "") {
        self.url = url
        self.text = text
    }

    var title: String {
        url?.lastPathComponent ?? String(localized: "Untitled")
    }

    /// Ein frischer, leerer Tab darf beim Öffnen einer Datei ersetzt werden.
    var isPristine: Bool {
        url == nil && !isDirty && text.isEmpty
    }
}
