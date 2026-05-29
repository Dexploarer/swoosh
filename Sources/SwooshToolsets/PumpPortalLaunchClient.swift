// SwooshToolsets/PumpPortalLaunchClient.swift — pump.fun launch prep client — 0.9Y
//
// PREPARE-ONLY. Pins the token logo + metadata to pump.fun's IPFS endpoint
// (POST https://pump.fun/api/ipfs, no key) and returns the metadata URI.
// It deliberately does NOT call the PumpPortal trade/create endpoint — no
// transaction is built, signed, or broadcast here, so no funds move. Wiring
// the create + signing path is a separate, custody-gated follow-up.
//
// Rule 7: this client never accepts or handles private keys / seed phrases.
// Network uses an injectable URLSession, matching DtourFeeSweepEngine.

import Foundation

public struct PumpPortalLaunchClient: Sendable {
    public enum LaunchPrepError: Error, LocalizedError, Sendable {
        case missingImage
        case ipfsUploadFailed(String)
        case noMetadataURI

        public var errorDescription: String? {
            switch self {
            case .missingImage: return "A logo image is required to prepare a pump.fun launch."
            case .ipfsUploadFailed(let why): return "IPFS metadata upload failed: \(why)"
            case .noMetadataURI: return "pump.fun IPFS response did not contain a metadata URI."
            }
        }
    }

    /// pump.fun's public IPFS pinning endpoint (no API key required).
    public static let ipfsEndpoint = "https://pump.fun/api/ipfs"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Pins logo + metadata to IPFS and returns the resulting metadata URI.
    /// This is the only network call in the prepare flow; it moves no funds.
    public func uploadMetadata(
        name: String,
        symbol: String,
        description: String,
        imageData: Data,
        mimeType: String,
        twitter: String?,
        telegram: String?,
        website: String?
    ) async throws -> String {
        guard !imageData.isEmpty else { throw LaunchPrepError.missingImage }
        guard let url = URL(string: Self.ipfsEndpoint) else {
            throw LaunchPrepError.ipfsUploadFailed("bad endpoint URL")
        }

        let boundary = "swoosh-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: [
                ("name", name),
                ("symbol", symbol),
                ("description", description),
                ("twitter", twitter ?? ""),
                ("telegram", telegram ?? ""),
                ("website", website ?? ""),
                ("showName", "true"),
            ],
            fileField: "file",
            fileName: "logo.\(Self.fileExtension(for: mimeType))",
            fileMime: mimeType,
            fileData: imageData
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LaunchPrepError.ipfsUploadFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LaunchPrepError.ipfsUploadFailed("HTTP \(http.statusCode): \(body.prefix(200))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchPrepError.ipfsUploadFailed("unparseable response")
        }
        // pump.fun returns { metadataUri } (sometimes nested under metadata).
        if let uri = json["metadataUri"] as? String, !uri.isEmpty { return uri }
        if let uri = json["uri"] as? String, !uri.isEmpty { return uri }
        if let meta = json["metadata"] as? [String: Any], let uri = meta["uri"] as? String, !uri.isEmpty {
            return uri
        }
        throw LaunchPrepError.noMetadataURI
    }

    // MARK: - multipart helpers

    private static func multipartBody(
        boundary: String,
        fields: [(String, String)],
        fileField: String,
        fileName: String,
        fileMime: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        let dashes = "--\(boundary)\r\n"
        for (key, value) in fields {
            body.append(dashes.data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append(dashes.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(fileMime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private static func fileExtension(for mime: String) -> String {
        switch mime.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return "png"
        }
    }
}
