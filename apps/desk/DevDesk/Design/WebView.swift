import SwiftUI
import WebKit

/// One local HTML file, shown as itself. `dev:arch` writes self-contained pages, so the view loads a single
/// `file:` URL with read access to nothing else, and refuses every navigation away from it: a diagram is a
/// document to look at, not a browser the app has to own the behaviour of.
struct WebView: NSViewRepresentable {
    let file: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        load(into: view, context.coordinator)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != file else { return }
        load(into: view, context.coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func load(into view: WKWebView, _ coordinator: Coordinator) {
        coordinator.loaded = file
        view.loadFileURL(file, allowingReadAccessTo: file)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?

        /// The file it was given, and nothing after it: a link inside a diagram opens in the browser, where a link
        /// belongs, rather than navigating the pane away from the document it is showing.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.isFileURL { return decisionHandler(.allow) }
            if action.navigationType == .linkActivated, url.scheme == "https" { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}
