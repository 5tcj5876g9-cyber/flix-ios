import SwiftUI
import WebKit

/// The site itself, inside a real WKWebView. Persistent data store means the
/// service worker and HTTP cache survive restarts, so the shell opens offline
/// with the pages the user already visited.
struct WebShellView: UIViewRepresentable {
    static let homeURL = URL(string: "https://flix.cat-pan.workers.dev/")!

    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var sniffer: MediaSniffer
    @Binding var reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(downloads: downloads, sniffer: sniffer)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // The page checks this flag to render "download in the app" instead of
        // dead mirrors. Set before any document script runs.
        let flag = WKUserScript(
            source: "window.FLIX_APP = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(flag)

        // Runs in every frame, cross-origin iframes included. That is the only
        // way to see the media URL a third-party player resolves internally.
        let snifferScript = WKUserScript(
            source: Self.snifferSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(snifferScript)
        config.userContentController.add(context.coordinator, name: "flix")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.027, green: 0.027, blue: 0.039, alpha: 1)
        webView.load(URLRequest(url: Self.homeURL, cachePolicy: .returnCacheDataElseLoad))
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastReloadToken != reloadToken else { return }
        context.coordinator.lastReloadToken = reloadToken
        webView.reload()
    }

    /// Watches <video> elements and network calls for m3u8/mp4 URLs, then posts
    /// them to the native side. Written as a plain string because it must run in
    /// the page's own context, not in the app.
    private static let snifferSource = """
    (function () {
      if (window.__flixSniffer) return;
      window.__flixSniffer = true;

      function send(url) {
        try {
          if (!url || !/\\.(m3u8|mp4)/i.test(url)) return;
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.flix) {
            window.webkit.messageHandlers.flix.postMessage({ action: 'media', url: String(url) });
          }
        } catch (e) {}
      }

      function scan() {
        var nodes = document.querySelectorAll('video, source');
        for (var i = 0; i < nodes.length; i++) {
          var node = nodes[i];
          if (node.currentSrc) send(node.currentSrc);
          if (node.src) send(node.src);
        }
      }

      var timer = setInterval(scan, 1200);
      setTimeout(function () { clearInterval(timer); }, 600000);

      var originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function () {
          var args = arguments;
          var probe = args[0];
          try {
            var raw = typeof probe === 'string' ? probe : (probe && probe.url) || '';
            send(raw);
          } catch (e) {}
          return originalFetch.apply(this, args).then(function (response) {
            try { send((response && response.url) || ''); } catch (e) {}
            return response;
          });
        };
      }

      var originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        try { send(String(url)); } catch (e) {}
        return originalOpen.apply(this, arguments);
      };
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let downloads: DownloadManager
        private let sniffer: MediaSniffer
        weak var webView: WKWebView?
        var lastReloadToken = 0

        init(downloads: DownloadManager, sniffer: MediaSniffer) {
            self.downloads = downloads
            self.sniffer = sniffer
        }

        // flixapp://download?url=...&title=... is how the site hands a media URL
        // to the native downloader without leaving the page.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme?.lowercased() == "flixapp" {
                handleDeepLink(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func handleDeepLink(_ url: URL) {
            guard url.host == "download" else { return }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let target = components?.queryItems?.first(where: { $0.name == "url" })?.value
            let title = components?.queryItems?.first(where: { $0.name == "title" })?.value
            guard let target, !target.isEmpty else { return }
            Task { @MainActor in
                downloads.enqueue(urlString: target, suggestedTitle: title)
                sniffer.clear()
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "flix", let payload = message.body as? [String: Any] else { return }

            if let action = payload["action"] as? String, action == "media",
               let url = payload["url"] as? String {
                Task { @MainActor in
                    sniffer.add(urlString: url)
                }
                return
            }

            if let action = payload["action"] as? String, action == "download",
               let url = payload["url"] as? String {
                let title = payload["title"] as? String
                Task { @MainActor in
                    downloads.enqueue(urlString: url, suggestedTitle: title)
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
