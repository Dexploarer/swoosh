// SwooshAPI/PairingInstallPage.swift — install-aware iPhone pairing page

import Foundation

struct PairingPageQuery: Decodable {
    let host: String
    let pairing: String
    let app: String?
    let min_ios_version: String?
    let install: String?
    let callback: String?
    let setup_url: String?
    let code: String?
}

func pairingInstallPage(query: PairingPageQuery) -> String {
    let deepLink = pairingDeepLink(query: query)
    let installURL = sanitizedURLString(query.install)
    let installButton = installURL.map {
        #"<a class="button secondary" href="\#(htmlEscape($0))">Install or Update</a>"#
    } ?? ""
    let deeplinkLiteral = javaScriptLiteral(deepLink)

    return """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Detour</title>
    <style>
    :root { color-scheme: dark; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background: #050505;
      color: #f4f4f3;
      font: 17px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    }
    main {
      width: min(88vw, 360px);
      text-align: center;
    }
    h1 {
      margin: 0 0 12px;
      font-size: 32px;
      letter-spacing: 0;
    }
    p {
      margin: 0 0 22px;
      color: #c6c6c3;
      line-height: 1.38;
    }
    .button {
      display: block;
      margin: 12px 0;
      padding: 15px 18px;
      border-radius: 8px;
      background: #b5522d;
      color: white;
      text-decoration: none;
      font-weight: 700;
    }
    .secondary {
      background: #f1f1ef;
      color: #0a0a0a;
    }
    </style>
    </head>
    <body>
    <main>
    <h1>Detour</h1>
    <p>Opening Detour. If it is not installed, install or update it, then scan again.</p>
    <a class="button" href="\(htmlEscape(deepLink))">Open Detour</a>
    \(installButton)
    </main>
    <script>
    setTimeout(function () { window.location.href = \(deeplinkLiteral); }, 250);
    </script>
    </body>
    </html>
    """
}

private func pairingDeepLink(query: PairingPageQuery) -> String {
    var components = URLComponents()
    components.scheme = "swoosh"
    components.host = "pair"
    components.queryItems = [
        URLQueryItem(name: "host", value: query.host),
        URLQueryItem(name: "pairing", value: query.pairing),
        URLQueryItem(name: "callback", value: query.callback),
        URLQueryItem(name: "setup_url", value: query.setup_url),
        URLQueryItem(name: "code", value: query.code),
        URLQueryItem(name: "app", value: query.app ?? "ai.swoosh.app.ios"),
        URLQueryItem(name: "min_ios_version", value: query.min_ios_version ?? "0.5")
    ]
    return components.url?.absoluteString ?? ""
}

private func sanitizedURLString(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          ["https", "itms-apps"].contains(scheme) else {
        return nil
    }
    return value
}

private func htmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func javaScriptLiteral(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let encoded = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return encoded
}
