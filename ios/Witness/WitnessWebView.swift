import SwiftUI
import WebKit

/// The app itself: a WKWebView pointed at the local server. The page is the same one as on the web;
/// the app adds three things a web page can't do for itself here:
///  - camera and microphone access without a second, per-page permission prompt,
///  - saving a finished recording through the share sheet (Save Video, AirDrop, Files…),
///  - opening outside links in Safari.
struct WitnessWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(home: url) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true                  // the camera preview and takes play in the page, not full screen
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()                     // keeps the downloaded subtitle model between launches
        let ucc = cfg.userContentController
        ucc.add(context.coordinator, name: "witness")
        ucc.addUserScript(WKUserScript(
            source: "window.WITNESS_APP = 'ios'; document.documentElement?.classList.add('ios-app');",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = UIColor(named: "LaunchBackground")
        wv.scrollView.backgroundColor = UIColor(named: "LaunchBackground")
        wv.scrollView.bounces = false
        wv.allowsBackForwardNavigationGestures = false
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true } // Safari › Develop on a Mac
        #endif
        context.coordinator.webView = wv
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let home: URL
        weak var webView: WKWebView?
        init(home: URL) { self.home = home }

        // The app's own pages (and the blob: URLs it makes for recordings) load here; anything else opens in Safari.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = action.request.url else { return decisionHandler(.cancel) }
            if u.host == home.host && u.port == home.port { return decisionHandler(.allow) }
            if action.targetFrame?.isMainFrame ?? true, ["http", "https", "mailto"].contains(u.scheme ?? "") {
                UIApplication.shared.open(u)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        // iOS has already asked for the camera and microphone on the app's behalf; don't ask again for the page.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host == home.host && origin.port == (home.port ?? 0) ? .grant : .deny)
        }

        // If the web content process is killed (memory, backgrounding), reload rather than show a blank page.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.load(URLRequest(url: home))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Diagnostics.runIfAsked(in: webView)
        }

        // Messages from the page (see "native app" in index.html).
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "save", let name = body["name"] as? String, let b64 = body["data"] as? String,
               let data = Data(base64Encoded: b64) {
                share(data, named: name)
            }
        }

        /// Write the recording to a temporary file and hand it to the share sheet.
        private func share(_ data: Data, named name: String) {
            let safe = name.replacingOccurrences(of: "/", with: "-")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(safe.isEmpty ? "witness.mp4" : safe)
            do { try data.write(to: file, options: .atomic) } catch { return }
            guard let wv = webView, let root = wv.window?.rootViewController else { return }
            var top = root
            while let p = top.presentedViewController { top = p }
            let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = wv            // iPad shows it as a popover
            sheet.popoverPresentationController?.sourceRect = CGRect(x: wv.bounds.midX, y: wv.bounds.maxY - 80, width: 1, height: 1)
            top.present(sheet, animated: true)
        }
    }
}
