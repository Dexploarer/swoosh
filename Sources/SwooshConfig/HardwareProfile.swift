// SwooshConfig/HardwareProfile.swift — System detection and MLX capacity check
//
// Preflight: OS, CPU, memory, disk, tools, dependencies, local model capacity.
// "Swoosh should classify models by role, not reject smaller models."

import Foundation

// MARK: - Hardware profile

public struct HardwareProfile: Sendable {
    public let osVersion: String
    public let cpuArchitecture: CPUArchitecture
    public let cpuName: String
    public let totalMemoryGB: Double
    public let availableMemoryGB: Double
    public let availableDiskGB: Double
    public let hasAppleSilicon: Bool

    // Detected tools
    public let hasGit: Bool
    public let hasXcodeTools: Bool
    public let hasDocker: Bool
    public let hasNode: Bool
    public let hasPython: Bool
    public let hasHomebrew: Bool

    // Local model capacity
    public let recommendedLocalModels: [LocalModelRecommendation]
}

public enum CPUArchitecture: String, Codable, Sendable {
    case arm64   // Apple Silicon
    case x86_64  // Intel
    case unknown
}

public struct LocalModelRecommendation: Sendable {
    public let sizeLabel: String    // "3B", "7B", "14B", "32B", "70B"
    public let parameterCount: Int  // billions
    public let fits: ModelFit
    public let role: ModelRole
    public let note: String
}

public enum ModelFit: String, Sendable {
    case recommended
    case feasible
    case marginal
    case notRecommended
}

public enum ModelRole: String, Codable, Sendable, CaseIterable {
    case router           // intent classification, tool arg drafting
    case memoryExtractor  // memory candidate extraction
    case coder            // code generation, editing
    case planner          // multi-step planning
    case chat             // conversational assistant
    case embedder         // embedding generation
    case vision           // image understanding
    case transcriber      // speech-to-text
}

// MARK: - Hardware detector

public struct HardwareDetector {
    public init() {}

    public func detect() -> HardwareProfile {
        let totalMem = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)

        return HardwareProfile(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            cpuArchitecture: detectArchitecture(),
            cpuName: detectCPUName(),
            totalMemoryGB: totalMem,
            availableMemoryGB: totalMem * 0.7, // conservative estimate
            availableDiskGB: detectAvailableDisk(),
            hasAppleSilicon: detectArchitecture() == .arm64,
            hasGit: commandExists("git"),
            hasXcodeTools: commandExists("xcode-select"),
            hasDocker: commandExists("docker"),
            hasNode: commandExists("node"),
            hasPython: commandExists("python3"),
            hasHomebrew: commandExists("brew"),
            recommendedLocalModels: recommendModels(memoryGB: totalMem)
        )
    }

    // MARK: - MLX local model capacity

    private func recommendModels(memoryGB: Double) -> [LocalModelRecommendation] {
        var recs: [LocalModelRecommendation] = []

        // 3B — always fits on Apple Silicon
        recs.append(LocalModelRecommendation(
            sizeLabel: "3B", parameterCount: 3,
            fits: memoryGB >= 8 ? .recommended : .feasible,
            role: .router,
            note: "Fast local router for intent classification, risk scoring, extraction."
        ))

        // 7B
        if memoryGB >= 8 {
            recs.append(LocalModelRecommendation(
                sizeLabel: "7B", parameterCount: 7,
                fits: memoryGB >= 16 ? .recommended : .feasible,
                role: .chat,
                note: "Good local chat and summarization model."
            ))
        }

        // 14B
        if memoryGB >= 16 {
            recs.append(LocalModelRecommendation(
                sizeLabel: "14B", parameterCount: 14,
                fits: memoryGB >= 32 ? .recommended : .feasible,
                role: .coder,
                note: "Strong local coding model. Recommended for Swift development."
            ))
        }

        // 32B
        if memoryGB >= 32 {
            recs.append(LocalModelRecommendation(
                sizeLabel: "32B", parameterCount: 32,
                fits: memoryGB >= 64 ? .recommended : .marginal,
                role: .planner,
                note: "Quantized planning/reasoning model. May be slow on 32 GB."
            ))
        }

        // 70B
        if memoryGB >= 64 {
            recs.append(LocalModelRecommendation(
                sizeLabel: "70B", parameterCount: 70,
                fits: memoryGB >= 128 ? .feasible : .marginal,
                role: .planner,
                note: "Large model. Requires significant memory and patience."
            ))
        } else {
            recs.append(LocalModelRecommendation(
                sizeLabel: "70B", parameterCount: 70,
                fits: .notRecommended,
                role: .planner,
                note: "Not recommended locally. Use cloud provider."
            ))
        }

        return recs
    }

    // MARK: - System detection helpers

    private func detectArchitecture() -> CPUArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }

    private func detectCPUName() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func detectAvailableDisk() -> Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home.path),
              let freeSpace = attrs[.systemFreeSize] as? Int64 else {
            return 0
        }
        return Double(freeSpace) / (1024 * 1024 * 1024)
    }

    private func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
