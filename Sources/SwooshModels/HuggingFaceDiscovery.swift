// SwooshModels/HuggingFaceDiscovery.swift — Live model discovery from Hugging Face — 0.9T
//
// Queries the HF API to find models the user doesn't have in the curated catalog.
// Filters by pipeline_tag (task), library (gguf/mlx), and sorts by downloads.

import Foundation

// MARK: - HF API types

struct HFModelInfo: Decodable, Sendable {
    let id: String
    let likes: Int?
    let downloads: Int?
    let tags: [String]?
    let pipeline_tag: String?
    let library_name: String?
    let modelId: String?
}

// MARK: - Pipeline tag mapping

extension ModelCapability {
    /// Maps our capability to HF pipeline_tag values
    var hfPipelineTags: [String] {
        switch self {
        // Text
        case .textGeneration, .coding, .toolCalling, .structuredOutput, .translation, .judge, .guard_:
            return ["text-generation"]
        case .codeCompletion:
            return ["text-generation", "fill-mask"]
        case .classification, .sentimentAnalysis:
            return ["text-classification"]
        case .summarization:
            return ["summarization", "text2text-generation"]
        case .namedEntityRecognition:
            return ["token-classification"]
        case .questionAnswering:
            return ["question-answering"]
        // Vision
        case .vision, .ocr, .documentLayout:
            return ["image-text-to-text", "visual-question-answering"]
        case .objectDetection:
            return ["object-detection"]
        case .imageSegmentation:
            return ["image-segmentation"]
        case .depthEstimation:
            return ["depth-estimation"]
        case .imageClassification:
            return ["image-classification"]
        // Audio
        case .speechToText:
            return ["automatic-speech-recognition"]
        case .textToSpeech, .voiceCloning, .voiceDesign:
            return ["text-to-speech", "text-to-audio"]
        case .vad, .diarization, .audioSeparation:
            return ["audio-classification"]
        case .soundEffects:
            return ["text-to-audio"]
        // Generation
        case .imageGeneration, .imageEditing:
            return ["text-to-image"]
        case .imageUpscaling:
            return ["image-to-image"]
        case .videoGeneration:
            return ["text-to-video"]
        case .musicGeneration:
            return ["text-to-audio"]
        case .threeD:
            return ["text-to-3d", "image-to-3d"]
        // Retrieval
        case .embedding:
            return ["feature-extraction", "sentence-similarity"]
        case .reranking:
            return ["text-classification"]
        }
    }
}

// MARK: - Discovery actor

public actor HuggingFaceDiscovery {

    private let baseURL = "https://huggingface.co/api/models"
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Discover models for a capability, filtered by format
    public func discover(
        capability: ModelCapability,
        format: ModelFormat = .gguf,
        limit: Int = 20
    ) async throws -> [CatalogEntry] {
        let tags = capability.hfPipelineTags
        var allResults: [CatalogEntry] = []

        for tag in tags {
            let library = format == .mlx ? "mlx" : format.rawValue
            var components = URLComponents(string: baseURL)!
            components.queryItems = [
                URLQueryItem(name: "pipeline_tag", value: tag),
                URLQueryItem(name: "library", value: library),
                URLQueryItem(name: "sort", value: "downloads"),
                URLQueryItem(name: "direction", value: "-1"),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ]

            guard let url = components.url else { continue }
            let (data, _) = try await session.data(from: url)
            let models = try JSONDecoder().decode([HFModelInfo].self, from: data)

            for model in models {
                if let entry = Self.toCatalogEntry(model, capability: capability, format: format) {
                    allResults.append(entry)
                }
            }
        }

        return allResults
    }

    /// Convert HF model info to a CatalogEntry
    private static func toCatalogEntry(
        _ model: HFModelInfo,
        capability: ModelCapability,
        format: ModelFormat
    ) -> CatalogEntry? {
        let modelID = model.modelId ?? model.id
        let name = modelID.components(separatedBy: "/").last ?? modelID

        // Estimate params + memory from name heuristics
        let size = estimateSize(name)

        return CatalogEntry(
            id: "hf-\(modelID.replacingOccurrences(of: "/", with: "-").lowercased())",
            name: name,
            family: modelID.components(separatedBy: "/").first ?? "Unknown",
            version: "latest",
            parameterCount: size.params,
            sizeTier: size.tier,
            estimatedMemoryGB: size.memoryGB,
            capabilities: [capability],
            formats: [format],
            sources: [.huggingFace],
            defaultRoles: capability.defaultRoles,
            license: extractLicense(model.tags ?? []),
            installCommands: [.huggingFace: "huggingface-cli download \(modelID)"],
            description: "Discovered from Hugging Face. \(model.downloads ?? 0) downloads.",
            huggingFaceID: modelID,
            isCurated: false
        )
    }

    /// Estimate model size from name patterns like "7B", "0.6B", "350M".
    /// Heuristic — only fires on the 27 patterns in the table below. Patterns
    /// outside the table (e.g. `5B`, `6B`, `33B`, `64B`, `1.3B`) silently
    /// fall through to the conservative `medium / 5 GB` default; surface
    /// any miss by adding a row.
    ///
    /// Matching is anchored: the character immediately before the pattern
    /// (if any) must NOT be a digit or `.` — otherwise "1.7B" would falsely
    /// match the "7B" row and "1.7B-instruct" would be misreported as
    /// `.medium / 5 GB`. Real HF IDs like `Qwen-1.7B-Instruct` need to land
    /// on `.small / 1.2 GB`, not jump up a tier.
    ///
    /// Internal (not private) so `HuggingFaceDiscoveryTests` can exercise
    /// every row + the unknown-fallback path.
    static func estimateSize(_ name: String) -> SizeEstimate {
        let upper = name.uppercased()

        for row in sizeTable where containsAnchored(upper, pattern: row.pattern) {
            return SizeEstimate(params: row.params, tier: row.tier, memoryGB: row.memoryGB)
        }
        return SizeEstimate(params: "Unknown", tier: .medium, memoryGB: 5.0) // Conservative default
    }

    /// Result of `estimateSize`. Named struct (instead of a 3-tuple) so the
    /// public surface stays under SwiftLint's `large_tuple` threshold and
    /// callers don't break when the schema grows.
    struct SizeEstimate: Sendable, Equatable {
        let params: String
        let tier: ModelSizeTier
        let memoryGB: Double
    }

    private struct SizePatternRow: Sendable {
        let pattern: String
        let params: String
        let tier: ModelSizeTier
        let memoryGB: Double
    }

    /// 27-row size-pattern table — matches the largest pattern first so
    /// "70B-instruct-1B" lands on 70B, not 1B. Adding a row is the way to
    /// fix a miss (e.g. when a new family ships a `33B` variant).
    private static let sizeTable: [SizePatternRow] = [
        SizePatternRow(pattern: "235B", params: "235B", tier: .massive, memoryGB: 130),
        SizePatternRow(pattern: "70B", params: "70B", tier: .massive, memoryGB: 45),
        SizePatternRow(pattern: "32B", params: "32B", tier: .xlarge, memoryGB: 20),
        SizePatternRow(pattern: "30B", params: "30B", tier: .xlarge, memoryGB: 18),
        SizePatternRow(pattern: "27B", params: "27B", tier: .xlarge, memoryGB: 17),
        SizePatternRow(pattern: "22B", params: "22B", tier: .xlarge, memoryGB: 14),
        SizePatternRow(pattern: "14B", params: "14B", tier: .large, memoryGB: 9),
        SizePatternRow(pattern: "13B", params: "13B", tier: .large, memoryGB: 8.5),
        SizePatternRow(pattern: "12B", params: "12B", tier: .large, memoryGB: 8),
        SizePatternRow(pattern: "9B", params: "9B", tier: .medium, memoryGB: 6),
        SizePatternRow(pattern: "8B", params: "8B", tier: .medium, memoryGB: 5.5),
        SizePatternRow(pattern: "7B", params: "7B", tier: .medium, memoryGB: 5),
        SizePatternRow(pattern: "4B", params: "4B", tier: .small, memoryGB: 3),
        SizePatternRow(pattern: "3B", params: "3B", tier: .small, memoryGB: 2),
        SizePatternRow(pattern: "2B", params: "2B", tier: .small, memoryGB: 1.5),
        SizePatternRow(pattern: "1.7B", params: "1.7B", tier: .small, memoryGB: 1.2),
        SizePatternRow(pattern: "1.5B", params: "1.5B", tier: .small, memoryGB: 1),
        SizePatternRow(pattern: "1B", params: "1B", tier: .micro, memoryGB: 0.7),
        SizePatternRow(pattern: "0.8B", params: "0.8B", tier: .micro, memoryGB: 0.5),
        SizePatternRow(pattern: "0.6B", params: "0.6B", tier: .micro, memoryGB: 0.4),
        SizePatternRow(pattern: "0.5B", params: "0.5B", tier: .micro, memoryGB: 0.35),
        SizePatternRow(pattern: "0.3B", params: "0.3B", tier: .nano, memoryGB: 0.2),
        SizePatternRow(pattern: "500M", params: "500M", tier: .micro, memoryGB: 0.35),
        SizePatternRow(pattern: "350M", params: "350M", tier: .nano, memoryGB: 0.25),
        SizePatternRow(pattern: "250M", params: "250M", tier: .nano, memoryGB: 0.2),
        SizePatternRow(pattern: "137M", params: "137M", tier: .nano, memoryGB: 0.1),
        SizePatternRow(pattern: "82M", params: "82M", tier: .nano, memoryGB: 0.05)
    ]

    /// Returns true iff `pattern` appears in `source` AND the character
    /// immediately preceding the first match (if any) is neither a digit
    /// nor `.`. Prevents `1.7B` from matching against the `7B` row,
    /// `350M` from masking `0.35B` patterns, and so on.
    static func containsAnchored(_ source: String, pattern: String) -> Bool {
        var searchStart = source.startIndex
        while let range = source.range(of: pattern, range: searchStart..<source.endIndex) {
            if range.lowerBound == source.startIndex {
                return true
            }
            let prev = source[source.index(before: range.lowerBound)]
            if !prev.isNumber && prev != "." {
                return true
            }
            // False match (preceded by a digit or dot); skip past the
            // first character of this hit and keep scanning.
            searchStart = source.index(after: range.lowerBound)
        }
        return false
    }

    /// Extract license from HF tags. Internal for test access.
    static func extractLicense(_ tags: [String]) -> String {
        for tag in tags {
            if tag.hasPrefix("license:") {
                return tag.replacingOccurrences(of: "license:", with: "")
            }
        }
        return "Unknown"
    }
}
