// SwooshCapabilities/CapabilityStatus.swift
// Version: 0.9R
//
// Sendable view-model used by the settings UI to render a per-modality
// status row: which provider is active, whether it runs locally, and
// whether the current platform supports it at all. Computed off the
// main actor so SwiftUI views can refresh from a published snapshot.

import Foundation

public struct CapabilityRow: Sendable, Identifiable {
    public enum Modality: String, Sendable, CaseIterable {
        case vision, translation, embedding, imageGen
        public var displayName: String {
            switch self {
            case .vision:      return "Vision"
            case .translation: return "Translation"
            case .embedding:   return "Embeddings"
            case .imageGen:    return "Image generation"
            }
        }
        public var systemImage: String {
            switch self {
            case .vision:      return "eye"
            case .translation: return "character.bubble"
            case .embedding:   return "square.stack.3d.up"
            case .imageGen:    return "paintpalette"
            }
        }
    }

    public let modality: Modality
    public let activeProviderID: String
    public let activeProviderDisplayName: String
    public let isLocal: Bool
    public let isAvailableOnDevice: Bool
    public let notes: String?

    public var id: String { modality.rawValue }

    public init(
        modality: Modality,
        activeProviderID: String,
        activeProviderDisplayName: String,
        isLocal: Bool,
        isAvailableOnDevice: Bool,
        notes: String? = nil
    ) {
        self.modality = modality
        self.activeProviderID = activeProviderID
        self.activeProviderDisplayName = activeProviderDisplayName
        self.isLocal = isLocal
        self.isAvailableOnDevice = isAvailableOnDevice
        self.notes = notes
    }
}

public struct CapabilitySnapshot: Sendable {
    public let rows: [CapabilityRow]
    public init(rows: [CapabilityRow]) { self.rows = rows }
}

public enum CapabilityAvailability {
    public static var appleTranslationAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) { return true }
        return false
    }
    public static var imagePlaygroundAvailable: Bool {
        if #available(macOS 15.2, iOS 18.2, *) { return true }
        return false
    }
    public static var visionDepthAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) { return true }
        return false
    }
}
