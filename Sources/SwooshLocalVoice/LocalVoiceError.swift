// SwooshLocalVoice/LocalVoiceError.swift — 0.9R Public errors

import Foundation

public enum LocalVoiceError: Error, CustomStringConvertible, Equatable {
    case engineNotReady(String)
    case backendNotAvailable(String)
    case modelLoadFailed(String)
    case synthesisFailed(String)

    public var description: String {
        switch self {
        case .engineNotReady(let m):      return "Local voice engine not ready: \(m)"
        case .backendNotAvailable(let m): return "Backend not available: \(m)"
        case .modelLoadFailed(let m):     return "Failed to load voice model: \(m)"
        case .synthesisFailed(let m):     return "Speech synthesis failed: \(m)"
        }
    }
}
