// SwooshModels/HFDatasetEntry.swift — HuggingFace dataset catalog entry — 0.9T

import Foundation

/// A dataset discovered from the Hugging Face Datasets API.
public struct HFDatasetEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let author: String
    public let downloads: Int
    public let likes: Int
    public let tags: [String]
    public let sizeBytes: Int64?
    public let lastModified: Date?
    public let description: String?
    public let taskCategories: [String]
    public let license: String?
    public let citation: String?

    public var formattedSize: String {
        guard let bytes = sizeBytes else { return "Unknown" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}
