// SwooshSkills/BundledSkillLoader.swift — 0.9S Read markdown skills off disk
//
// Bundled skills ship as plain markdown files with a YAML frontmatter
// header — the same shape the Hermes / agentskills.io convention uses,
// chosen so we can paste community skills in unchanged.
//
//     ---
//     name: review-pr
//     description: Walk through a PR diff, flag risks, draft review notes
//     category: coding
//     tags: [review, git]
//     trust: promoted
//     platforms: [macOS, iOS, linux]
//     triggers: ["review this PR", "look at the diff"]
//     ---
//
//     ## When to use
//     ...
//
//     ## Procedure
//     ...
//
// Only a tiny subset of YAML is recognised — `key: value`, inline
// `[a, b]` lists, and block lists.

import Foundation

/// Loads bundled `.md` skills from a directory into the store. Idempotent
/// per skill ID — re-running just re-saves with the latest content.
public actor BundledSkillLoader {
    private let store: any SkillStoring
    public let directory: URL

    public init(store: any SkillStoring, directory: URL) {
        self.store = store
        self.directory = directory
    }

    /// Default location: `<repo-root>/Skills/Bundled/` when running from
    /// the package's working directory. Callers running from a built app
    /// should pass an explicit URL.
    public static func defaultDirectory() -> URL {
        URL(fileURLWithPath: "Skills/Bundled", isDirectory: true,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    @discardableResult
    public func loadAll() async throws -> [SkillDocument] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let entries = skillMarkdownFiles(in: directory)
        var loaded: [SkillDocument] = []
        for url in entries {
            let text = try String(contentsOf: url, encoding: .utf8)
            let relative = relativePath(for: url)
            let supportFiles = supportFiles(for: url)
            var skill = SkillMarkdownParser().parse(
                text,
                fileName: url.deletingPathExtension().lastPathComponent,
                sourceDirectory: url.deletingLastPathComponent().path,
                supportingFiles: supportFiles
            ).document
            skill.provenance = SkillProvenance(source: .builtIn)
            skill.trust = skill.trust == .draft ? .promoted : skill.trust
            skill = withStableID(skill, id: "bundled.\(relative.replacingOccurrences(of: "/", with: "."))")
            try await store.save(skill)
            loaded.append(skill)
        }
        return loaded
    }

    // MARK: - Parsing

    private func withStableID(_ skill: SkillDocument, id: String) -> SkillDocument {
        var copy = skill
        // SkillDocument.id is `let`; round-trip through Codable to swap it.
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(copy)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            dict["id"] = id
            let updated = try JSONSerialization.data(withJSONObject: dict)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            copy = try decoder.decode(SkillDocument.self, from: updated)
        } catch {
            // Fall through with the UUID-derived ID; not fatal.
        }
        return copy
    }

    private func skillMarkdownFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "SKILL.md" || (url.deletingLastPathComponent() == root && url.pathExtension.lowercased() == "md") {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func relativePath(for url: URL) -> String {
        let root = directory.standardizedFileURL.path
        let path = url.deletingPathExtension().standardizedFileURL.path
        let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : url.deletingPathExtension().lastPathComponent
        return relative.isEmpty ? url.deletingPathExtension().lastPathComponent : relative
    }

    private func supportFiles(for skillFile: URL) -> [String] {
        let root = skillFile.deletingLastPathComponent()
        guard skillFile.lastPathComponent == "SKILL.md",
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }
        var files: [String] = []
        for case let url as URL in enumerator where url.lastPathComponent != "SKILL.md" {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let relative = url.path.hasPrefix(root.path)
                ? String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : url.lastPathComponent
            files.append(relative)
        }
        let siblingCommon = root.deletingLastPathComponent().appendingPathComponent("common", isDirectory: true)
        if let commonEnumerator = FileManager.default.enumerator(at: siblingCommon, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in commonEnumerator {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                let relative = url.path.hasPrefix(siblingCommon.path)
                    ? String(url.path.dropFirst(siblingCommon.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    : url.lastPathComponent
                files.append("../common/\(relative)")
            }
        }
        return Array(Set(files)).sorted()
    }
}
