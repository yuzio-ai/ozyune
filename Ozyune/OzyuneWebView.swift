import AppKit
import SwiftUI
import WebKit

struct OzyuneWebView: NSViewRepresentable {
    let url: URL

    /// Name of the script message handler bridging page-side agent signals to native code.
    private static let signalHandlerName = "ozyuneAgentSignals"

    /// Page-world observer: subclasses `WebSocket` so server-to-client frames are
    /// offered to the native classifier.
    ///
    /// It only *adds* a `message` listener to each socket the page creates — it
    /// never intercepts, rewrites, or delays traffic the page itself sees, and
    /// non-string frames are ignored. Frames are filtered against the classifier's
    /// own marker vocabulary before crossing the bridge, so the assistant's
    /// streaming chunks cost a string `includes` in the page and nothing more.
    ///
    /// The marker list is generated from ``AgentSignalClassifier/frameMarkers``
    /// rather than duplicated here: one vocabulary, two consumers.
    private static let signalObserverScript = """
    (() => {
        if (window.__ozyuneAgentSignalsInstalled) { return; }
        window.__ozyuneAgentSignalsInstalled = true;

        const handler = window.webkit && window.webkit.messageHandlers
            && window.webkit.messageHandlers.ozyuneAgentSignals;
        const OriginalWebSocket = window.WebSocket;
        if (!handler || !OriginalWebSocket) { return; }

        const markers = \(AgentSignalClassifier.javaScriptFrameMarkers);

        const forward = (data) => {
            if (typeof data !== "string") { return; }
            if (!markers.some((marker) => data.includes(marker))) { return; }
            try { handler.postMessage(data); } catch (error) { /* page is going away */ }
        };

        // A real subclass rather than a function returning the native instance:
        // `instanceof`, `ws.constructor`, the static CONNECTING/OPEN/CLOSING/CLOSED
        // constants and `class X extends WebSocket` all keep working.
        //
        // Observation must never break the page's own connections, so a failure
        // to install leaves the native constructor in place.
        try {
            class ObservedWebSocket extends OriginalWebSocket {
                constructor(...args) {
                    super(...args);
                    this.addEventListener("message", (event) => forward(event.data));
                }
            }

            window.WebSocket = ObservedWebSocket;
        } catch (error) {
            window.WebSocket = OriginalWebSocket;
        }
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let userContent = WKUserContentController()
        userContent.add(context.coordinator, contentWorld: .page, name: Self.signalHandlerName)
        userContent.addUserScript(WKUserScript(
            source: Self.signalObserverScript,
            injectionTime: .atDocumentStart,
            // The dsh Web UI renders in the top frame; sockets opened inside
            // subframes are a documented blind spot.
            forMainFrameOnly: true
        ))
        configuration.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: signalHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            // Xcode 27's SDK imports this requirement as `for navigationAction:`;
            // the older `forNavigationAction navigationAction:` spelling still
            // compiles but no longer witnesses the optional requirement, so
            // WebKit stopped calling it and `target=_blank` / `window.open`
            // silently did nothing.
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping ([URL]?) -> Void
        ) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection

            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        // MARK: - Agent signal bridge

        /// Receives WebSocket frame text from the page-world observer,
        /// classifies it, and hands reportable signals to the notification
        /// controller.
        ///
        /// Only frames carrying a marker reach this point (the page filters
        /// first), so a `nil` verdict here means the marker vocabulary no longer
        /// matches the wire format — exactly what the debug trace is for.
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == OzyuneWebView.signalHandlerName,
                  let frameText = message.body as? String else { return }

            let signal = AgentSignalClassifier.classify(frameText: frameText)

            if AgentSignalDebug.isEnabled {
                Self.debugLog(frameText: frameText, signal: signal)
            }

            guard let signal else { return }
            Task { @MainActor in
                NotificationController.shared.handle(signal)
            }
        }

        /// With `OZYUNE_DEBUG_SIGNALS=1`, traces every marker-bearing frame and
        /// its verdict to Console, so a dsh wire-format change shows up as
        /// `signal=none` lines instead of silent silence.
        private static func debugLog(frameText: String, signal: AgentSignal?) {
            let excerpt = frameText.prefix(400)
            NSLog(
                "[OzyuneSignals] signal=%@ frame=%@",
                signal?.rawValue ?? "none",
                String(excerpt)
            )
        }
    }
}
