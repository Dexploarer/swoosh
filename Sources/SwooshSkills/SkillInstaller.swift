// SwooshSkills/SkillInstaller.swift — Install skills from files, URLs, and hubs
import Foundation

public enum SkillInstallTrust: String, Codable, Sendable {
    case draft
    case reviewed
    case promoted

    var skillTrust: SkillTrust {
        switch self {
        case .draft: .draft
        case .reviewed: .reviewed
        case .promoted: .promoted
        }
    }
}

public struct SkillInstallResult: Codable, Sendable {
    public let id: String
    public let title: String
    public let source: String
    public let trust: SkillTrust
    public let warnings: [String]
    public let supportingFiles: [String]
}

public actor SkillInstaller {
    private let store: any SkillStoring
    private let installDirectory: URL
    private let parser: SkillMarkdownParser
    private let guardrail: SkillGuard

    public init(
        store: any SkillStoring,
        installDirectory: URL? = nil,
        parser: SkillMarkdownParser = SkillMarkdownParser(),
        guardrail: SkillGuard = SkillGuard(allowImportedSkills: true)
    ) {
        self.store = store
        self.installDirectory = installDirectory ?? SkillInstaller.defaultInstallDirectory()
        self.parser = parser
        self.guardrail = guardrail
    }

    /// Cross-platform default location for installed skill assets.
    private static func defaultInstallDirectory() -> URL {
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/skill-assets", isDirectory: true)
        #else
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ai.swoosh.agent/skill-assets", isDirectory: true)
        #endif
    }

    public func install(source: String, name: String? = nil, trust: SkillInstallTrust = .reviewed) async throws -> SkillInstallResult {
        let payload = try await loadPayload(source: source)
        var parsed = parser.parse(
            payload.markdown,
            fileName: name ?? payload.fileName,
            sourceDirectory: payload.sourceDirectory?.path,
            supportingFiles: payload.supportingFiles
        ).document
        parsed.trust = trust.skillTrust
        parsed.provenance = SkillProvenance(source: .imported)

        let id = stableImportedID(name: name ?? parsed.title, source: source)
        let assetDir = installDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)
        try payload.markdown.write(to: assetDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        if let sourceDirectory = payload.sourceDirectory {
            try copySupportFiles(from: sourceDirectory, to: assetDir)
        }
        parsed.sourceDirectory = assetDir.path
        parsed.supportingFiles = supportFiles(in: assetDir)
        parsed = withStableID(parsed, id: id)

        let violations = guardrail.validate(parsed)
        let dangerous = violations.filter(\.blocksSkillInstall)
        guard dangerous.isEmpty else {
            throw SkillInstallError.blocked(dangerous.map(\.description))
        }

        try await store.save(parsed)
        return SkillInstallResult(
            id: parsed.id,
            title: parsed.title,
            source: source,
            trust: parsed.trust,
            warnings: violations.map(\.description),
            supportingFiles: parsed.supportingFiles
        )
    }

    private func loadPayload(source: String) async throws -> SkillPayload {
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            return try await loadRemote(url: URL(string: source).unwrap(or: SkillInstallError.invalidSource(source)))
        }
        if source.hasPrefix("github:") {
            let path = String(source.dropFirst("github:".count))
            let parts = path.split(separator: "/", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { throw SkillInstallError.invalidSource(source) }
            let raw = "https://raw.githubusercontent.com/\(parts[0])/\(parts[1])/main/\(parts[2].trimmingCharacters(in: CharacterSet(charactersIn: "/")))/SKILL.md"
            return try await loadRemote(url: URL(string: raw).unwrap(or: SkillInstallError.invalidSource(source)))
        }
        return try loadLocal(url: URL(fileURLWithPath: NSString(string: source).expandingTildeInPath))
    }

    private func loadRemote(url: URL) async throws -> SkillPayload {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SkillInstallError.fetchFailed(url.absoluteString)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SkillInstallError.invalidMarkdown(url.absoluteString)
        }
        return SkillPayload(markdown: text, fileName: url.deletingPathExtension().lastPathComponent, sourceDirectory: nil, supportingFiles: [])
    }

    private func loadLocal(url: URL) throws -> SkillPayload {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw SkillInstallError.invalidSource(url.path)
        }
        if isDirectory.boolValue {
            let skillFile = url.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillFile.path) else {
                throw SkillInstallError.invalidSource("\(url.path) has no SKILL.md")
            }
            let text = try String(contentsOf: skillFile, encoding: .utf8)
            return SkillPayload(markdown: text, fileName: url.lastPathComponent, sourceDirectory: url, supportingFiles: supportFiles(in: url))
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return SkillPayload(markdown: text, fileName: url.deletingPathExtension().lastPathComponent, sourceDirectory: url.deletingLastPathComponent(), supportingFiles: [])
    }

    private func copySupportFiles(from source: URL, to destination: URL) throws {
        for file in supportFiles(in: source) {
            let src = source.appendingPathComponent(file)
            let dst = destination.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
        }
    }

    private func supportFiles(in directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var files: [String] = []
        for case let url as URL in enumerator where url.lastPathComponent != "SKILL.md" {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let relative = url.path.hasPrefix(directory.path)
                ? String(url.path.dropFirst(directory.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : url.lastPathComponent
            files.append(relative)
        }
        return files.sorted()
    }

    private func stableImportedID(name: String, source: String) -> String {
        let base = "\(name)-\(source)"
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "imported.\(String(base.prefix(96)))"
    }

    private func withStableID(_ skill: SkillDocument, id: String) -> SkillDocument {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(skill)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            dict["id"] = id
            let updated = try JSONSerialization.data(withJSONObject: dict)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SkillDocument.self, from: updated)
        } catch {
            return skill
        }
    }
}

private struct SkillPayload: Sendable {
    let markdown: String
    let fileName: String
    let sourceDirectory: URL?
    let supportingFiles: [String]
}

public enum SkillInstallError: Error, Sendable, LocalizedError {
    case invalidSource(String)
    case invalidMarkdown(String)
    case fetchFailed(String)
    case blocked([String])

    public var errorDescription: String? {
        switch self {
        case .invalidSource(let source): "invalid skill source: \(source)"
        case .invalidMarkdown(let source): "skill source is not UTF-8 markdown: \(source)"
        case .fetchFailed(let source): "failed to fetch skill: \(source)"
        case .blocked(let warnings): "skill blocked by security scan: \(warnings.joined(separator: "; "))"
        }
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
