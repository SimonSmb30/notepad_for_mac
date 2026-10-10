import Foundation
import UniformTypeIdentifiers
import WebKit

/// Beliefert die Vorschau über ein eigenes Schema, damit sie ohne Dateizugriff
/// und ohne Netz auskommt:
/// - `/app/<Name>` ist eine Datei aus dem Programm (Renderer, Bibliotheken, Schriften),
/// - `/doc/<Pfad>` ist der Text des Tabs oder eine Datei aus dessen Ordner.
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "notepad-preview"
    private static let origin = scheme + "://local"

    /// Alles, was eine Vorschau ausmacht; ändert sich etwas davon, wird neu geladen.
    struct Content: Equatable {
        var documentURL: URL
        var kind: PreviewKind
        var text: String
        var themeCSS: String
        var allowsScripts: Bool
        var allowsNetwork: Bool

        /// Die Adresse, unter der diese Vorschau lädt.
        var pageURL: URL {
            var document = URLComponents(string: PreviewSchemeHandler.origin)!
            document.path = "/doc" + documentURL.standardizedFileURL.path
            // HTML-Dateien sind selbst die Seite, alles andere rendert `preview.html`.
            guard kind != .html else { return document.url! }
            var page = URLComponents(string: PreviewSchemeHandler.origin)!
            page.path = "/app/preview.html"
            page.queryItems = [
                URLQueryItem(name: "kind", value: kind.rawValue),
                URLQueryItem(name: "doc", value: document.url!.absoluteString),
                URLQueryItem(name: "ext", value: documentURL.pathExtension),
                URLQueryItem(name: "lang", value: Bundle.main.preferredLocalizations.first),
            ]
            return page.url!
        }
    }

    var content: Content?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let reply = content.map { self.reply(to: url, $0) } ?? Reply(status: 404)
        var headers = reply.headers
        headers["Cache-Control"] = "no-store"
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(reply.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private struct Reply {
        var status = 200
        var data = Data()
        var headers: [String: String] = [:]
    }

    private func reply(to url: URL, _ content: Content) -> Reply {
        let path = url.path
        if path.hasPrefix("/app/") {
            let name = url.lastPathComponent
            if name == "theme.css" {
                return Reply(data: Data(content.themeCSS.utf8), headers: ["Content-Type": "text/css; charset=utf-8"])
            }
            // Xcode legt alle Dateien flach ab, deshalb zählt nur der Name.
            guard let file = Bundle.main.url(forResource: name, withExtension: nil),
                  let data = try? Data(contentsOf: file) else { return Reply(status: 404) }
            var headers = ["Content-Type": Self.mimeType(for: file.pathExtension)]
            if name == "preview.html" {
                headers["Content-Security-Policy"] = Self.rendererPolicy(content)
            }
            return Reply(data: data, headers: headers)
        }

        guard path.hasPrefix("/doc/") else { return Reply(status: 404) }
        let file = URL(fileURLWithPath: String(path.dropFirst(4))).standardizedFileURL
        let document = content.documentURL.standardizedFileURL
        var reply: Reply
        if file.path == document.path {
            // Der Text aus dem Editor, auch wenn er noch nicht gesichert ist.
            reply = Reply(data: Data(content.text.utf8))
        } else {
            // Nur der Ordner der Datei: Eine fremde HTML-Seite soll nicht den ganzen Mac lesen können.
            let folder = document.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard file.resolvingSymlinksInPath().path.hasPrefix(folder + "/") else { return Reply(status: 403) }
            guard let data = try? Data(contentsOf: file) else { return Reply(status: 404) }
            reply = Reply(data: data)
        }
        let type = Self.mimeType(for: file.pathExtension)
        reply.headers["Content-Type"] = type
        if type.hasPrefix("text/html"), let policy = Self.documentPolicy(content) {
            reply.headers["Content-Security-Policy"] = policy
        }
        return reply
    }

    // MARK: - Regeln

    /// Für die eigene Seite: Skripte nur aus dem Programm, damit rohes HTML in
    /// Markdown oder einem Notebook nichts ausführen kann.
    private static func rendererPolicy(_ content: Content) -> String {
        let network = content.allowsNetwork ? " https: http:" : ""
        return [
            "default-src 'none'",
            "script-src \(origin)/app/ 'wasm-unsafe-eval'",
            "style-src \(scheme): 'unsafe-inline'",
            "img-src \(scheme): data: blob:\(network)",
            "font-src \(scheme): data:",
            "media-src \(scheme): data: blob:\(network)",
            "connect-src \(scheme):",
        ].joined(separator: "; ")
    }

    /// Für HTML-Dateien, je nach Einstellung. `nil`: keine Einschränkung.
    private static func documentPolicy(_ content: Content) -> String? {
        var rules: [String] = []
        if !content.allowsNetwork {
            rules.append("default-src \(scheme): data: blob: 'unsafe-inline' 'unsafe-eval'")
        }
        if !content.allowsScripts {
            rules.append("script-src 'none'")
        }
        return rules.isEmpty ? nil : rules.joined(separator: "; ")
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": "text/html; charset=utf-8"
        case "js", "cjs", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "svg": "image/svg+xml"
        case "woff2": "font/woff2"
        default:
            UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "text/plain; charset=utf-8"
        }
    }
}
