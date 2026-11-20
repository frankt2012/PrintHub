import SwiftUI
import WebKit

struct CameraWebView: NSViewRepresentable {
    let url: URL
    let onReady: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onFailure: onFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()

        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: Self.injectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        controller.add(context.coordinator, name: "camera")
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .black
        webView.isInspectable = true
        context.coordinator.webView = webView
        context.coordinator.load(url)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.loadIfNeeded(url, in: nsView)
    }

    private static let injectionScript = """
    (() => {
      const apply = () => {
        const el = document.querySelector('video-stream');
        const video = (el && el.video) || document.querySelector('video');
        if (!video) return false;

        document.body.style.margin = '0';
        document.body.style.background = '#000';
        document.body.style.overflow = 'hidden';

        if (!document.getElementById('printhub-camera-style')) {
          const style = document.createElement('style');
          style.id = 'printhub-camera-style';
          style.textContent = `
            video { outline: none !important; }
            video::-webkit-media-controls,
            video::-webkit-media-controls-enclosure,
            video::-webkit-media-controls-panel,
            video::-webkit-media-controls-start-playback-button {
              display: none !important;
              -webkit-appearance: none !important;
            }
          `;
          document.head.appendChild(style);
        }

        if (el) {
          el.style.width = '100vw';
          el.style.height = '100vh';
        }

        video.controls = false;
        video.muted = true;
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.objectFit = 'contain';
        video.style.background = '#000';

        const info = el && el.querySelector('.info');
        if (info) info.style.display = 'none';

        if (video.videoWidth > 0 && video.readyState >= 2) {
          try { window.webkit.messageHandlers.camera.postMessage('ready'); } catch (e) {}
          return true;
        }
        return false;
      };

      if (!apply()) {
        const timer = setInterval(() => {
          if (apply()) clearInterval(timer);
        }, 500);
        setTimeout(() => clearInterval(timer), 30000);
      }
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let onReady: () -> Void
        private let onFailure: (String) -> Void
        private var loadedURL: URL?
        private var reportedReady = false

        weak var webView: WKWebView?

        init(onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
            self.onReady = onReady
            self.onFailure = onFailure
        }

        func load(_ url: URL) {
            loadedURL = url
            reportedReady = false
            webView?.load(URLRequest(url: url))
        }

        func loadIfNeeded(_ url: URL, in webView: WKWebView) {
            self.webView = webView
            guard loadedURL != url else { return }
            load(url)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "camera" else { return }
            guard let value = message.body as? String else { return }

            if value == "ready", !reportedReady {
                reportedReady = true
                Task { @MainActor in
                    onReady()
                }
            } else if value.hasPrefix("error:") {
                let reason = String(value.dropFirst("error:".count))
                Task { @MainActor in
                    onFailure(reason)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                onFailure(error.localizedDescription)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                onFailure(error.localizedDescription)
            }
        }
    }
}
