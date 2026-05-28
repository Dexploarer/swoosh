// SwooshCloudGaming/WebGameBridge.swift — WKWebView cloud gaming bridge
//
// Embeds web-based cloud gaming services (Xbox Cloud Gaming, GeForce NOW,
// Amazon Luna, Boosteroid) via WKWebView. Captures frames by drawing
// the <video> element to an offscreen canvas, and injects input via
// JavaScript shims (keyboard, mouse, W3C Gamepad API override).
// 0.5A – May 2026

#if canImport(WebKit)
import WebKit
import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - WebGameBridge
// ═══════════════════════════════════════════════════════════════════

@MainActor
public final class WebGameBridge: NSObject, GameStreamProviding, WKNavigationDelegate {
    private let service: CloudGamingService
    public private(set) var webView: WKWebView?
    private var _status: StreamStatus = .disconnected
    private var frameCount: Int = 0
    private var startTime: Date?

    public init(service: CloudGamingService) {
        self.service = service
        super.init()
    }

    // ── GameStreamProviding ──────────────────────────────────────

    public nonisolated var isConnected: Bool {
        get async { await MainActor.run { _status == .playing } }
    }

    public nonisolated var status: StreamStatus {
        get async { await MainActor.run { _status } }
    }

    public nonisolated var info: StreamInfo {
        get async {
            await MainActor.run {
                let fps: Double
                if let start = startTime, frameCount > 0 {
                    let elapsed = Date().timeIntervalSince(start)
                    fps = elapsed > 0 ? Double(frameCount) / elapsed : 0
                } else {
                    fps = 0
                }
                return StreamInfo(source: .web(service), estimatedFPS: fps)
            }
        }
    }

    // ── WebView setup ────────────────────────────────────────────

    /// Create and configure the WKWebView. Returns it for embedding in SwiftUI.
    public func configureWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        // Persistent data store for auth cookies
        let store = WKWebsiteDataStore.default()
        config.websiteDataStore = store

        // Inject the gamepad shim at document start
        let shimScript = WKUserScript(
            source: GamepadBridge.gamepadShimJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(shimScript)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self

        // Apply service-specific user agent
        if let ua = service.userAgentOverride {
            wv.customUserAgent = ua
        }

        self.webView = wv
        return wv
    }

    /// Navigate to the service's stream URL.
    public func loadService() {
        guard let wv = webView else { return }
        _status = .connecting
        startTime = Date()
        let request = URLRequest(url: service.streamURL)
        wv.load(request)
    }

    // ── Frame capture ────────────────────────────────────────────

    public func captureFrame() async throws -> Data {
        guard let wv = self.webView else {
            throw WebGameError.webViewNotConfigured
        }

        let result = try await wv.evaluateJavaScript(Self.frameCaptureJS)
        guard let base64 = result as? String,
              let data = Data(base64Encoded: base64) else {
            throw WebGameError.noVideoElement
        }
        self.frameCount += 1
        return data
    }

    // ── Input injection ──────────────────────────────────────────

    public func sendInput(_ input: GameInput) async throws {
        guard let wv = self.webView else {
            throw WebGameError.webViewNotConfigured
        }

        let js: String
        switch input {
        case .keyDown(let key):
            js = "document.dispatchEvent(new KeyboardEvent('keydown', {key:'\(key)', code:'\(key)', bubbles:true}));"
        case .keyUp(let key):
            js = "document.dispatchEvent(new KeyboardEvent('keyup', {key:'\(key)', code:'\(key)', bubbles:true}));"
        case .mouseMove(let dx, let dy):
            js = """
            (function() {
                var el = document.querySelector('video') || document.querySelector('canvas') || document.body;
                var r = el.getBoundingClientRect();
                el.dispatchEvent(new MouseEvent('mousemove', {
                    clientX: r.left + r.width/2 + \(dx),
                    clientY: r.top + r.height/2 + \(dy),
                    bubbles: true
                }));
            })();
            """
        case .mouseClick(let button, let down):
            let btnNum = button == .right ? 2 : button == .middle ? 1 : 0
            let eventType = down ? "mousedown" : "mouseup"
            js = """
            (function() {
                var el = document.querySelector('video') || document.querySelector('canvas') || document.body;
                el.dispatchEvent(new MouseEvent('\(eventType)', {button:\(btnNum), bubbles:true}));
            })();
            """
        case .mouseScroll(let dx, let dy):
            js = "document.querySelector('video,canvas,body').dispatchEvent(new WheelEvent('wheel', {deltaX:\(dx), deltaY:\(dy), bubbles:true}));"
        case .gamepad:
            // Gamepad state is injected via the gamepad bridge's periodic update JS
            js = ""
        }

        if !js.isEmpty {
            try await wv.evaluateJavaScript(js)
        }
    }

    // ── Navigation delegate ──────────────────────────────────────

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        _status = .connecting
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _status = .playing
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        _status = .error
    }

    // ── JavaScript constants ─────────────────────────────────────

    /// Captures the first <video> element as JPEG base64 via an offscreen canvas.
    private static let frameCaptureJS = """
    (function() {
        var video = document.querySelector('video');
        if (!video || video.readyState < 2) return null;
        var canvas = document.createElement('canvas');
        canvas.width = 256;
        canvas.height = 256;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(video, 0, 0, 256, 256);
        var dataUrl = canvas.toDataURL('image/jpeg', 0.6);
        return dataUrl.split(',')[1];
    })();
    """
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum WebGameError: Error, LocalizedError {
    case webViewNotConfigured
    case noVideoElement
    case jsError(String)

    public var errorDescription: String? {
        switch self {
        case .webViewNotConfigured: "WebView not configured — call configureWebView() first"
        case .noVideoElement:       "No <video> element found or video not ready"
        case .jsError(let msg):     "JavaScript error: \(msg)"
        }
    }
}
#endif
