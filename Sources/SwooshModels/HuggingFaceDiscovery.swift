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
        let (params, tier, mem) = estimateSize(name)

        return CatalogEntry(
            id: "hf-\(modelID.replacingOccurrences(of: "/", with: "-").lowercased())",
            name: name,
            family: modelID.components(separatedBy: "/").first ?? "Unknown",
            version: "latest",
            parameterCount: params,
            sizeTier: tier,
            estimatedMemoryGB: mem,
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
    static func estimateSize(_ name: String) -> (params: String, tier: ModelSizeTier, memGB: Double) {
        let upper = name.uppercased()

        // Match patterns like "14B", "0.6B", "350M"
        let patterns: [(String, String, ModelSizeTier, Double)] = [
            ("235B", "235B", .massive, 130), ("70B", "70B", .massive, 45),
            ("32B", "32B", .xlarge, 20), ("30B", "30B", .xlarge, 18),
            ("27B", "27B", .xlarge, 17), ("22B", "22B", .xlarge, 14),
            ("14B", "14B", .large, 9), ("13B", "13B", .large, 8.5),
            ("12B", "12B", .large, 8), ("9B", "9B", .medium, 6),
            ("8B", "8B", .medium, 5.5), ("7B", "7B", .medium, 5),
            ("4B", "4B", .small, 3), ("3B", "3B", .small, 2),
            ("2B", "2B", .small, 1.5), ("1.7B", "1.7B", .small, 1.2),
            ("1.5B", "1.5B", .small, 1), ("1B", "1B", .micro, 0.7),
            ("0.8B", "0.8B", .micro, 0.5), ("0.6B", "0.6B", .micro, 0.4),
            ("0.5B", "0.5B", .micro, 0.35), ("0.3B", "0.3B", .nano, 0.2),
            ("500M", "500M", .micro, 0.35), ("350M", "350M", .nano, 0.25),
            ("250M", "250M", .nano, 0.2), ("137M", "137M", .nano, 0.1),
            ("82M", "82M", .nano, 0.05),
        ]

        for (pattern, params, tier, mem) in patterns where containsAnchored(upper, pattern: pattern) {
            return (params, tier, mem)
        }
        return ("Unknown", .medium, 5.0) // Conservative default
    }

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

