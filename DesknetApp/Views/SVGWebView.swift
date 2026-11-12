import AppKit
import SwiftUI
import WebKit

/// Renders captured SVG with WebKit. The markup comes from whatever server the captured app talks to,
/// so it is treated as hostile. Four layers keep it from running code or reaching the network:
/// 1. It is shown through `<img>`, where browsers run no SVG scripts and load no external resources.
/// 2. A Content-Security-Policy allows only the inline `data:` image and inline styles.
/// 3. A content rule list blocks every URL except `about:` and `data:`.
/// 4. JavaScript is off, the data store is ephemeral, and navigation away from the page is cancelled.
struct SVGWebView: NSViewRepresentable {
    let data: Data
    /// false: thumbnail. Clicks and scrolls pass through to SwiftUI (the card's button and scroll view).
    var interactive = false
    /// Sheet only: lets toolbar buttons drive the zoom.
    var controller: SVGZoomController?

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedData: Data?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only the page we load ourselves; links and redirects go nowhere.
            decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SVGWebKitView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let view = SVGWebKitView(frame: .zero, configuration: configuration)
        view.passesEventsThrough = !interactive
        view.allowsMagnification = interactive
        view.allowsBackForwardNavigationGestures = false
        view.underPageBackgroundColor = .clear
        view.navigationDelegate = context.coordinator
        view.setAccessibilityLabel("SVG image")
        controller?.webView = view
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: SVGWebKitView, context: Context) {
        // Cards are reused when another request is selected.
        if context.coordinator.loadedData != data {
            load(into: nsView, coordinator: context.coordinator)
        }
    }

    private func load(into view: SVGWebKitView, coordinator: Coordinator) {
        coordinator.loadedData = data
        let html = Self.html(for: data)
        Task { @MainActor in
            // If the rule list fails to compile, layers 1, 2 and 4 still apply.
            if let rules = await SVGSandbox.ruleList(), !view.hasRuleList {
                view.configuration.userContentController.add(rules)
                view.hasRuleList = true
            }
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    /// The SVG fills the view, scaled to fit, on a checkerboard so transparent and dark artwork stay visible.
    static func html(for data: Data) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
        body {
          background-color: #ffffff;
          background-image: linear-gradient(45deg, #e6e6e6 25%, transparent 25%, transparent 75%, #e6e6e6 75%),
                            linear-gradient(45deg, #e6e6e6 25%, transparent 25%, transparent 75%, #e6e6e6 75%);
          background-size: 16px 16px;
          background-position: 0 0, 8px 8px;
        }
        img { display: block; width: 100%; height: 100%; object-fit: contain; }
        </style></head>
        <body><img alt="" src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
        """
    }
}

final class SVGWebKitView: WKWebView {
    var passesEventsThrough = false
    fileprivate var hasRuleList = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesEventsThrough ? nil : super.hitTest(point)
    }
}

/// Compiles the block-everything rule list once and shares it between web views.
@MainActor
enum SVGSandbox {
    private static var compiled: WKContentRuleList?
    private static var attempted = false

    private static let rules = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^(about|data):"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """

    static func ruleList() async -> WKContentRuleList? {
        if attempted { return compiled }
        attempted = true
        compiled = try? await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: "dev.desknet.svg-sandbox", encodedContentRuleList: rules)
        return compiled
    }
}

/// Zoom buttons for the SVG sheet. Magnification 1 is "fit", because the SVG fills the view.
@MainActor
final class SVGZoomController {
    weak var webView: WKWebView?
    private static let step: CGFloat = 1.25
    private static let maxZoom: CGFloat = 16

    func zoomIn() { zoom(to: (webView?.magnification ?? 1) * Self.step) }
    func zoomOut() { zoom(to: (webView?.magnification ?? 1) / Self.step) }
    func fit() { zoom(to: 1) }

    private func zoom(to value: CGFloat) {
        guard let webView else { return }
        let center = NSPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        webView.setMagnification(min(max(value, 1), Self.maxZoom), centeredAt: center)
    }
}
