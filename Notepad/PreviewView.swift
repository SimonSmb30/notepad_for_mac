import AppKit
import SwiftUI
import WebKit

/// Die gerenderte Ansicht eines Tabs.
struct PreviewView: NSViewRepresentable {
    let content: PreviewSchemeHandler.Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator.handler, forURLScheme: PreviewSchemeHandler.scheme)
        // Nichts aus der Vorschau soll auf der Platte zurückbleiben.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.loaded != content else { return }
        coordinator.loaded = content
        coordinator.handler.content = content
        // Bis die Seite steht, scheint der Hintergrund des Editors durch statt einer weißen Fläche.
        webView.alphaValue = 0
        webView.load(URLRequest(url: content.pageURL))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let handler = PreviewSchemeHandler()
        var loaded: PreviewSchemeHandler.Content?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let loaded else {
                decisionHandler(.cancel)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if navigationAction.targetFrame?.isMainFrame == false {
                // Eingebettete Rahmen: Lokales immer, Fremdes nur mit erlaubtem Netz.
                let isLocal = [PreviewSchemeHandler.scheme, "about", "data", "blob"].contains(scheme)
                decisionHandler(isLocal || loaded.allowsNetwork ? .allow : .cancel)
                return
            }
            // Die Vorschau bleibt bei ihrer Datei; Links öffnet der Browser.
            if Self.withoutFragment(url) == Self.withoutFragment(loaded.pageURL) {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated, ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.alphaValue = 1
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.alphaValue = 1
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.alphaValue = 1
        }

        private static func withoutFragment(_ url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.fragment = nil
            return components?.string ?? url.absoluteString
        }
    }
}
