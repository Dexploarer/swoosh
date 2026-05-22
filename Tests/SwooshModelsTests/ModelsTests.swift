// Tests/SwooshModelsTests/ModelsTests.swift — SwooshModels
//
// Covers ModelSizeTier ordering and memory bands, HardwareProfile
// usable-memory + maxTier, ModelCatalog actor queries, and CatalogEntry
// Codable round-trips. The curated catalog data is exercised via the
// `compatible()` query which seeds it.

import Testing
import Foundation
@testable import SwooshModels

// MARK: - ModelSizeTier

@Suite("ModelSizeTier")
struct ModelSizeTierTests {

    @Test("Ordering is monotonic")
    func ordering() {
        let order: [ModelSizeTier] = [.nano, .micro, .small, .medium, .large, .xlarge, .massive]
        for i in 0..<(order.count - 1) {
            #expect(order[i] < order[i + 1])
        }
    }

    @Test("maxMemoryGB strictly increases by tier")
    func maxMemoryIncreases() {
        let order: [ModelSizeTier] = [.nano, .micro, .small, .medium, .large, .xlarge, .massive]
        for i in 0..<(order.count - 1) {
            #expect(order[i].maxMemoryGB < order[i + 1].maxMemoryGB)
        }
    }

    @Test("Codable round-trip")
    func codable() throws {
        for tier in ModelSizeTier.allCases {
            let data = try JSONEncoder().encode(tier)
            let decoded = try JSONDecoder().decode(ModelSizeTier.self, from: data)
            #expect(decoded == tier)
        }
    }
}

// MARK: - ModelFormat / Source / Role / Capability

@Suite("Model Enums Codable")
struct ModelEnumCodableTests {

    @Test("ModelFormat round-trips for every case")
    func modelFormat() throws {
        for value in ModelFormat.allCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ModelFormat.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("ModelSource round-trips for every case")
    func modelSource() throws {
        for value in ModelSource.allCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ModelSource.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("ModelRole round-trips for every case")
    func modelRole() throws {
        for value in ModelRole.allCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ModelRole.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("ModelCapability round-trips for every case")
    func modelCapability() throws {
        for value in ModelCapability.allCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ModelCapability.self, from: data)
            #expect(decoded == value)
        }
    }
}

// MARK: - HardwareProfile

@Suite("HardwareProfile")
struct HardwareProfileTests {

    @Test("Initialization preserves fields")
    func fields() {
        let p = HardwareProfile(
            chip: "Apple M4", totalMemoryGB: 32,
            gpuCores: 10, neuralEngineCores: 16, osVersion: "macOS 26"
        )
        #expect(p.chip == "Apple M4")
        #expect(p.totalMemoryGB == 32)
    }

    @Test("usableMemoryGB reserves ~4GB for OS")
    func usableMemory() {
        let p = HardwareProfile(chip: "x", totalMemoryGB: 32, gpuCores: 1, neuralEngineCores: 1, osVersion: "x")
        #expect(p.usableMemoryGB == 28)
    }

    @Test("usableMemoryGB floors at 2GB for tiny machines")
    func usableMemoryFloor() {
        let p = HardwareProfile(chip: "x", totalMemoryGB: 4, gpuCores: 1, neuralEngineCores: 1, osVersion: "x")
        #expect(p.usableMemoryGB == 2)
    }

    @Test("maxTier matches usable memory bands")
    func maxTierBands() {
        // 16GB total → 12GB usable → large band
        let p1 = HardwareProfile(chip: "x", totalMemoryGB: 16, gpuCores: 1, neuralEngineCores: 1, osVersion: "x")
        #expect(p1.maxTier == .large)

        // 8GB total → 4GB usable → small band
        let p2 = HardwareProfile(chip: "x", totalMemoryGB: 8, gpuCores: 1, neuralEngineCores: 1, osVersion: "x")
        #expect(p2.maxTier == .small)

        // 64GB total → 60GB usable → massive band
        let p3 = HardwareProfile(chip: "x", totalMemoryGB: 64, gpuCores: 1, neuralEngineCores: 1, osVersion: "x")
        #expect(p3.maxTier == .massive)

        // 4GB total → 2GB usable → micro band (< 5 boundary maps to small; 2 < 5 but >= 2 → small per `..<5` branch)
        let p4 = HardwareProfile(chip: "x", totalMemoryGB: 4, gpuCores: 1, neuralEngineCores: 1, osVersion: "x")
        #expect(p4.maxTier == .small)
    }

    @Test("detectCurrent returns a usable profile")
    func detect() {
        let p = HardwareProfile.detectCurrent()
        #expect(p.totalMemoryGB > 0)
        #expect(!p.osVersion.isEmpty)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = HardwareProfile(chip: "M4", totalMemoryGB: 16, gpuCores: 10,
                                        neuralEngineCores: 16, osVersion: "26")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HardwareProfile.self, from: data)
        #expect(decoded.chip == "M4")
        #expect(decoded.totalMemoryGB == 16)
    }
}

// MARK: - CatalogEntry

@Suite("CatalogEntry")
struct CatalogEntryTests {

    private func entry() -> CatalogEntry {
        CatalogEntry(
            id: "test-1b", name: "Test 1B", family: "Test", version: "1.0",
            parameterCount: "1B", sizeTier: .small, estimatedMemoryGB: 1.0,
            capabilities: [.textGeneration],
            formats: [.gguf],
            sources: [.ollama],
            defaultRoles: [.agent],
            license: "MIT",
            installCommands: [.ollama: "ollama pull test:1b"],
            description: "A test model"
        )
    }

    @Test("All fields preserved")
    func fields() {
        let e = entry()
        #expect(e.id == "test-1b")
        #expect(e.sizeTier == .small)
        #expect(e.estimatedMemoryGB == 1.0)
        #expect(e.capabilities.contains(.textGeneration))
        #expect(e.defaultRoles.contains(.agent))
        #expect(e.installCommands[.ollama] == "ollama pull test:1b")
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = entry()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CatalogEntry.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.capabilities == original.capabilities)
        #expect(decoded.defaultRoles == original.defaultRoles)
    }
}

// MARK: - ModelCatalog actor

@Suite("ModelCatalog")
struct ModelCatalogTests {

    /// A high-memory profile that admits every curated model so queries return data.
    private let bigHardware = HardwareProfile(
        chip: "Apple M4 Max", totalMemoryGB: 128,
        gpuCores: 40, neuralEngineCores: 16, osVersion: "macOS 26"
    )

    @Test("Catalog seeded with curated models")
    func seeded() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let compatible = await catalog.compatible()
        #expect(compatible.isEmpty == false)
    }

    @Test("Compatible filters by memory")
    func filteredByMemory() async {
        let tinyHardware = HardwareProfile(
            chip: "test", totalMemoryGB: 4, gpuCores: 1,
            neuralEngineCores: 1, osVersion: "x"
        )
        let catalog = ModelCatalog(hardware: tinyHardware)
        let compatible = await catalog.compatible()
        for entry in compatible {
            #expect(entry.estimatedMemoryGB <= tinyHardware.usableMemoryGB)
        }
    }

    @Test("forRole returns only matching role")
    func forRole() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let agents = await catalog.forRole(.agent)
        for entry in agents {
            #expect(entry.defaultRoles.contains(.agent))
        }
    }

    @Test("withCapability filters")
    func withCapability() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let coders = await catalog.withCapability(.coding)
        for entry in coders {
            #expect(entry.capabilities.contains(.coding))
        }
    }

    @Test("inTier filters")
    func inTier() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let smalls = await catalog.inTier(.small)
        for entry in smalls {
            #expect(entry.sizeTier == .small)
        }
    }

    @Test("atOrBelow returns subset bounded by tier")
    func atOrBelow() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let mediumOrBelow = await catalog.atOrBelow(.medium)
        for entry in mediumOrBelow {
            #expect(entry.sizeTier <= .medium)
        }
    }

    @Test("register adds an entry retrievable by id")
    func registerCustom() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let custom = CatalogEntry(
            id: "custom-x", name: "Custom X", family: "Custom", version: "1",
            parameterCount: "1B", sizeTier: .small, estimatedMemoryGB: 1,
            capabilities: [.textGeneration], formats: [.gguf], sources: [.huggingFace],
            defaultRoles: [.agent], license: "MIT",
            installCommands: [.huggingFace: "hf download custom/x"],
            description: "custom"
        )
        await catalog.register(custom)
        let fetched = await catalog.get("custom-x")
        #expect(fetched?.id == "custom-x")
    }

    @Test("get returns nil for unknown id")
    func getMissing() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let entry = await catalog.get("definitely-not-real-id-12345")
        #expect(entry == nil)
    }

    @Test("search matches name and id")
    func search() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let custom = CatalogEntry(
            id: "uniqueneedlexyz", name: "Unique Needle XYZ", family: "Needle", version: "1",
            parameterCount: "1B", sizeTier: .small, estimatedMemoryGB: 1,
            capabilities: [.textGeneration], formats: [.gguf], sources: [.huggingFace],
            defaultRoles: [.agent], license: "MIT", installCommands: [:],
            description: "needle"
        )
        await catalog.register(custom)
        let hits = await catalog.search("uniqueneedle")
        #expect(hits.contains { $0.id == "uniqueneedlexyz" })
    }

    @Test("summary returns role-grouped non-empty buckets")
    func summary() async {
        let catalog = ModelCatalog(hardware: bigHardware)
        let summary = await catalog.summary()
        for bucket in summary {
            #expect(!bucket.models.isEmpty)
            for entry in bucket.models {
                #expect(entry.defaultRoles.contains(bucket.role))
            }
        }
    }
}

// MARK: - UnifiedModelCatalog

@Suite("UnifiedModelCatalog")
struct UnifiedModelCatalogTests {

    @Test("interactive catalog contains cloud and local routes")
    func interactiveContainsCloudAndLocal() {
        let models = UnifiedModelCatalog.interactive
        #expect(models.contains { $0.id == ModelDefaults.routerModelID })
        #expect(models.contains { $0.modelID == ModelDefaults.openAIModelID && $0.providerID == ModelDefaults.openAIProviderID })
        #expect(models.contains { $0.modelID == ModelDefaults.localMLXModelID && $0.providerID == ModelDefaults.localMLXProviderID })
        #expect(models.contains { $0.modelID == ModelDefaults.localOpenAIModelID && $0.providerID == ModelDefaults.localOpenAIProviderID })
        #expect(UnifiedModelCatalog.all.contains { $0.modelID == ModelDefaults.phoneFunctionCallingModelID && $0.providerID == ModelDefaults.localOpenAIProviderID })
        #expect(!models.contains { $0.modelID == ModelDefaults.phoneFunctionCallingModelID })
    }

    @Test("auto route remains router-owned")
    func autoRoute() {
        let route = UnifiedModelCatalog.route(forCatalogID: ModelDefaults.routerModelID)
        #expect(route == nil)
    }

    @Test("MLX Gemma default routes to the Swift provider")
    func mlxGemmaRoute() {
        let route = UnifiedModelCatalog.route(forCatalogID: "\(ModelDefaults.localMLXProviderID):gemma4-e4b")
        #expect(route?.providerID == ModelDefaults.localMLXProviderID)
        #expect(route?.modelID == ModelDefaults.localMLXModelID)
    }

    @Test("modality buckets separate non-chat models")
    func modalityBuckets() {
        #expect(UnifiedModelCatalog.embeddings.contains { $0.modelID == "nomic-embed-text" })
        #expect(UnifiedModelCatalog.speechToText.contains { $0.capabilities.contains(.speechToText) })
        #expect(UnifiedModelCatalog.textToSpeech.contains { $0.capabilities.contains(.textToSpeech) })
        #expect(UnifiedModelCatalog.imageGeneration.contains { $0.capabilities.contains(.imageGeneration) })
    }

    @Test("chat route ignores non-chat catalog entries")
    func nonChatCatalogEntryHasNoChatRoute() {
        guard let speech = UnifiedModelCatalog.speechToText.first else {
            Issue.record("Missing speech-to-text catalog entry")
            return
        }
        guard let embedder = UnifiedModelCatalog.embeddings.first else {
            Issue.record("Missing embedding catalog entry")
            return
        }

        #expect(UnifiedModelCatalog.route(forCatalogID: speech.id) == nil)
        #expect(UnifiedModelCatalog.route(forCatalogID: embedder.id) == nil)
    }

    @Test("old Gemma models are not curated")
    func oldGemmaRemoved() {
        let oldIDs = ["gemma3:1b", "gemma3:4b", "gemma3:12b", "gemma-3n-E2B-it-int4"]
        let catalogText = ModelCatalog.curatedModels
            .flatMap { [$0.id, $0.ollamaTag, $0.huggingFaceID].compactMap { $0 } }
            .joined(separator: "\n")
        for id in oldIDs {
            #expect(!catalogText.contains(id))
        }
    }
}
