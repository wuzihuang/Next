import SwiftUI
import WebKit

/// Originkit's WebGL2 renderer runs locally behind the panel's THINKING slot.
struct GrainMassBackground: UIViewRepresentable {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.active = scenePhase == .active
        context.coordinator.reduced = reduceMotion
        context.coordinator.update(webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript("window.grainMass?.dispose()", completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var active = true
        var reduced = false
        private var ready = false
        private var appliedState: String?

        func load(_ webView: WKWebView) {
            ready = false
            appliedState = nil
            guard let url = Bundle.main.url(forResource: "GrainMass", withExtension: "html"),
                  let html = try? String(contentsOf: url, encoding: .utf8) else { return }
            webView.loadHTMLString(html, baseURL: nil)
        }

        func update(_ webView: WKWebView) {
            guard ready else { return }
            let state = "window.grainMass?.setState(\(active), \(reduced))"
            guard appliedState != state else { return }
            appliedState = state
            webView.evaluateJavaScript(state, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            update(webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            load(webView)
        }
    }
}
