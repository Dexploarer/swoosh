// SwooshToolsets/AudioDownloader.swift — 0.4A Audio source -> bytes helper
//
// Music providers return either a remote CDN URL (Suno) or a local
// temp-file URL (ElevenLabs, Stable Audio). `GenerateMusicTool` needs
// the bytes either way so it can stage them in MediaCacheDir alongside
// image/video/3D outputs. Protocol-based so tests can stub.

import Foundation

public protocol AudioDownloading: Sendable {
    func bytes(from url: URL) async throws -> Data
}

public struct URLSessionAudioDownloader: AudioDownloading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func bytes(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw AudioDownloadError.httpStatus(http.statusCode)
        }
        return data
    }
}

public enum AudioDownloadError: Error, CustomStringConvertible, Sendable {
    case httpStatus(Int)

    public var description: String {
        switch self {
        case .httpStatus(let code): return "Audio download HTTP \(code)"
        }
    }
}
