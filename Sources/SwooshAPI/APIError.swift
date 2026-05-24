// SwooshAPI/APIError.swift — 0.9S API-internal error taxonomy
//
// Thrown from runtime adapters (`APIRuntimeState`, route closures) and
// translated to HTTP status codes by `apiHTTPError` in `APIHelpers.swift`.

import Foundation

public enum APIError: Error, Sendable {
    case notFound(String)
    case unauthorized
    case badRequest(String)
    case internalError(String)
}
