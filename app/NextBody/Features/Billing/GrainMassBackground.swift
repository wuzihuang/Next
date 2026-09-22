import SwiftUI
import WebKit

/// Originkit's supplied WebGL2 renderer runs locally behind the native paywall.
/// No remote content, React runtime, account data, or purchase bridge enters this view.
struct GrainMassBackground: UIViewRepresentable {
    /// Where the mass sits. Framing only — every composition is the same simulation,
    /// palette and bloom, which is the point of reusing one renderer for both.
    enum Composition {
        /// Right half of an opaque dark page, clear of the CTA.
        case paywall
        /// Centred, on a transparent ground, for the THINKING slot on the panel.
        case thinking

        fileprivate var script: String? {
            switch self {
            case .paywall: return nil
            case .thinking: return "window.grainMassConfig={scale:104,offset:[0,0],transparent:true};"
            }
        }
    }

    var composition: Composition = .paywall
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let script = composition.script {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = composition == .paywall
            ? UIColor(red: 13 / 255, green: 17 / 255, blue: 20 / 255, alpha: 1) : .clear
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
