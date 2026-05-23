// SwooshCapabilities/CapabilityRouter+MediaGen.swift
// Version: 0.9R
//
// Video + 3D generation routing. Extracted from CapabilityRouter to keep
// the root router file under the LOC ceiling. Both modalities are
// cloud-only today (FAL.ai). Local executors can be added later by
// adding new enum cases and matching providers.

import Foundation
import SwooshImageGen

extension CapabilityRouter {

    // MARK: - Video generation

    public enum VideoChoice: String, Sendable, CaseIterable, Identifiable {
        case falVeo3            = "fal-veo3"
        case falKlingText       = "fal-kling-text"
        case falKlingImage      = "fal-kling-image"
        case falHunyuan         = "fal-hunyuan"
        case falLuma            = "fal-luma"

        public var id: String { rawValue }

        /// FAL model identifier used when constructing the request.
        public var modelID: String {
            switch self {
            case .falVeo3:        return "fal-ai/veo3"
            case .falKlingText:   return "fal-ai/kling-video/v2/master/text-to-video"
            case .falKlingImage:  return "fal-ai/kling-video/v2/master/image-to-video"
            case .falHunyuan:     return "fal-ai/hunyuan-video"
            case .falLuma:        return "fal-ai/luma-dream-machine"
            }
        }

        public var displayName: String {
            switch self {
            case .falVeo3:        return "FAL · Google Veo 3"
            case .falKlingText:   return "FAL · Kling 2.0 (text-to-video)"
            case .falKlingImage:  return "FAL · Kling 2.0 (image-to-video)"
            case .falHunyuan:     return "FAL · Hunyuan Video"
            case .falLuma:        return "FAL · Luma Dream Machine"
            }
        }

        public var isLocal: Bool { false }
    }

    public var currentVideoChoice: VideoChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.capabilities.video") ?? "fal-veo3"
            return VideoChoice(rawValue: raw) ?? .falVeo3
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.capabilities.video") }
    }

    /// Returns a configured video provider, or nil when no FAL key has
    /// been injected. Callers should surface a "Configure FAL key" UI
    /// affordance when nil.
    public func activeVideoProvider() -> (any VideoGenProviding)? {
        guard let keyProvider = falAPIKeyProvider else { return nil }
        let client = FALClient(apiKey: keyProvider)
        return FALVideoProvider(client: client)
    }

    public var isVideoConfigured: Bool { falAPIKeyProvider != nil }

    // MARK: - 3D generation

    public enum ThreeDChoice: String, Sendable, CaseIterable, Identifiable {
        case falTripo3D        = "fal-tripo3d"
        case falTrellis        = "fal-trellis"
        case falTripoSR        = "fal-triposr"
        case falHunyuan3D      = "fal-hunyuan3d"

        public var id: String { rawValue }

        public var modelID: String {
            switch self {
            case .falTripo3D:    return "fal-ai/tripo3d"
            case .falTrellis:    return "fal-ai/trellis"
            case .falTripoSR:    return "fal-ai/triposr"
            case .falHunyuan3D:  return "fal-ai/hunyuan3d/v2"
            }
        }

        public var displayName: String {
            switch self {
            case .falTripo3D:    return "FAL · Tripo3D"
            case .falTrellis:    return "FAL · Trellis"
            case .falTripoSR:    return "FAL · TripoSR"
            case .falHunyuan3D:  return "FAL · Hunyuan3D 2.0"
            }
        }

        public var isLocal: Bool { false }
    }

    public var currentThreeDChoice: ThreeDChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.capabilities.threeD") ?? "fal-tripo3d"
            return ThreeDChoice(rawValue: raw) ?? .falTripo3D
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.capabilities.threeD") }
    }

    public func activeThreeDProvider() -> (any ThreeDGenProviding)? {
        guard let keyProvider = falAPIKeyProvider else { return nil }
        let client = FALClient(apiKey: keyProvider)
        return FALThreeDProvider(client: client)
    }

    public var isThreeDConfigured: Bool { falAPIKeyProvider != nil }
}
