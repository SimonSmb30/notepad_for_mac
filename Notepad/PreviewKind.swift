import Foundation

/// Wie die Vorschau eine Datei darstellt. Die Namen kennt auch `Preview/preview.js`.
enum PreviewKind: String {
    case markdown, html, svg, table, json, yaml, toml, xml, notebook, mermaid, graphviz, diff

    /// `nil`, wenn es für die Datei keine Vorschau gibt.
    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "html", "htm": self = .html
        case "svg": self = .svg
        case "csv", "tsv": self = .table
        case "json", "geojson": self = .json
        case "yaml", "yml": self = .yaml
        case "toml": self = .toml
        case "xml", "plist": self = .xml
        case "ipynb": self = .notebook
        case "mmd", "mermaid": self = .mermaid
        case "dot", "gv": self = .graphviz
        case "diff", "patch": self = .diff
        default: return nil
        }
    }
}
