// SwooshProviders/ProviderErrorClassification.swift — 0.1A Error surfacing + quota classifier
//
// Two jobs:
//   1. Make `ProviderError` conform to `LocalizedError` so callers get a
//      human sentence instead of "SwooshProviders.ProviderError error 7".
//      `allRoutesFailed` folds in each attempt's reason — that opaque 500
//      is what hid a codex usage-limit failure during debugging.
//   2. Classify an HTTP failure body/status into the right case so a plan
//      quota cap ("you've hit your usage limit", insufficient_quota, 429
//      with a long reset) surfaces as `.quotaExceeded` distinct from a
//      transient `.rateLimited`. Mirrors detour's provider-quota-service.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - LocalizedError
// ═══════════════════════════════════════════════════════════════════

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured(let id):
            return "Provider \(id) is not configured."
        case .authMissing(_, let msg):
            return msg
        case .requestFailed(let id, let msg):
            return "\(id) request failed: \(msg)"
        case .responseParseFailed(let id, let msg):
            return "\(id) returned an unparseable response: \(msg)"
        case .rateLimited(let id, let retry):
            if let retry {
                return "\(id) is rate-limited; retry in \(retry)s."
            }
            return "\(id) is rate-limited."
        case .quotaExceeded(let id, let msg, let resetsAt):
            if let resetsAt {
                let when = ProviderError.resetFormatter.string(from: resetsAt)
                return "\(id) usage limit reached (resets \(when)): \(msg)"
            }
            return "\(id) usage limit reached: \(msg)"
        case .modelNotAvailable(let id, let model):
            return "\(id) has no model named \(model)."
        case .unsupportedEndpoint(let id, let endpoint):
            return "\(id) does not support \(endpoint)."
        case .allRoutesFailed(let attempts):
            guard !attempts.isEmpty else {
                return "No providers are configured for this role."
            }
            let reasons = attempts.map { attempt -> String in
                let why = (attempt.error as? LocalizedError)?.errorDescription
                    ?? attempt.error.localizedDescription
                return "\(attempt.route.providerID): \(why)"
            }
            return "All \(attempts.count) provider route(s) failed — " + reasons.joined(separator: "; ")
        case .networkError(let id, let msg):
            return "\(id) network error: \(msg)"
        }
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - HTTP failure classifier
// ═══════════════════════════════════════════════════════════════════

public extension ProviderError {

    /// Map an upstream HTTP failure to the most specific `ProviderError`.
    /// `status` is the HTTP code; `body` is the (possibly JSON) response
    /// body; `retryAfterHeader` is the raw `Retry-After` value if present.
    static func classifyHTTPFailure(
        providerID: ProviderID,
        status: Int,
        body: String,
        retryAfterHeader: String? = nil
    ) -> ProviderError {
        let lower = body.lowercased()

        // Plan/credit exhaustion — semantically distinct from a transient
        // 429. OpenAI uses `insufficient_quota`; ChatGPT/Codex and others
        // phrase it as "usage limit"/"quota"/"billing".
        let quotaMarkers = [
            "insufficient_quota", "usage limit", "usage_limit",
            "quota", "exceeded your current quota", "billing", "credit balance"
        ]
        if quotaMarkers.contains(where: lower.contains) {
            return .quotaExceeded(
                providerID,
                message: condensedMessage(from: body),
                resetsAt: nil
            )
        }

        if status == 429 {
            return .rateLimited(providerID, retryAfterSeconds: parseRetryAfter(retryAfterHeader))
        }
        if status == 401 || status == 403 {
            return .authMissing(providerID, condensedMessage(from: body))
        }
        return .requestFailed(providerID, condensedMessage(from: body))
    }

    /// Pull the `error.message` field out of a JSON error envelope, else
    /// return a trimmed/truncated copy of the raw body.
    private static func condensedMessage(from body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
    }

    private static func parseRetryAfter(_ header: String?) -> Int? {
        guard let header = header?.trimmingCharacters(in: .whitespaces) else { return nil }
        return Int(header)
    }
}
