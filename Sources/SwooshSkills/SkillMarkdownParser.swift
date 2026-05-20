// SwooshSkills/SkillMarkdownParser.swift — Parse agentskills-style markdown
import Foundation

public struct ParsedSkillMarkdown: Sendable {
    public let document: SkillDocument
    public let frontmatter: [String: String]
}

public struct SkillMarkdownParser: Sendable {
    public init() {}

    public func parse(_ text: String, fileName: String, sourceDirectory: String? = nil, supportingFiles: [String] = []) -> ParsedSkillMarkdown {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("---\n") {
            let afterOpen = normalized.dropFirst("---\n".count)
            if let closeRange = afterOpen.range(of: "\n---\n") {
                let frontmatter = String(afterOpen[..<closeRange.lowerBound])
                let body = String(afterOpen[closeRange.upperBound...])
                let fields = parseFields(frontmatter)
                return ParsedSkillMarkdown(
                    document: assemble(fields: fields, body: body, fileName: fileName, sourceDirectory: sourceDirectory, supportingFiles: supportingFiles),
                    frontmatter: fields.scalars
                )
            }
        }
        return ParsedSkillMarkdown(
            document: synthesize(fileName: fileName, body: normalized, sourceDirectory: sourceDirectory, supportingFiles: supportingFiles),
            frontmatter: [:]
        )
    }

    private func synthesize(fileName: String, body: String, sourceDirectory: String?, supportingFiles: [String]) -> SkillDocument {
        SkillDocument(
            title: fileName.replacingOccurrences(of: "-", with: " ").capitalized,
            description: firstLineOf(body, fallback: "Skill: \(fileName)"),
            category: .general,
            provenance: SkillProvenance(source: .imported),
            trust: .draft,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceDirectory: sourceDirectory,
            supportingFiles: supportingFiles
        )
    }

    private func assemble(
        fields: ParsedFields,
        body: String,
        fileName: String,
        sourceDirectory: String?,
        supportingFiles: [String]
    ) -> SkillDocument {
        let title = fields.scalar("name")
            ?? fields.scalar("title")
            ?? fileName.replacingOccurrences(of: "-", with: " ").capitalized
        let description = fields.scalar("description") ?? firstLineOf(body, fallback: title)
        let category = SkillCategory(rawValue: fields.scalar("category") ?? fields.scalar("metadata.hermes.category") ?? "general") ?? .general
        let tags = fields.list("tags") ?? fields.list("metadata.hermes.tags") ?? []
        let triggers = fields.list("triggers") ?? fields.list("trigger_patterns") ?? fields.list("metadata.hermes.triggers") ?? []
        let platforms = Set(fields.list("platforms") ?? ["macOS", "iOS", "linux"])
        let trust = SkillTrust(rawValue: fields.scalar("trust") ?? "draft") ?? .draft
        let requiredToolsets = fields.list("requires_toolsets") ?? fields.list("metadata.hermes.requires_toolsets") ?? []
        let requiredTools = fields.list("requires_tools") ?? fields.list("metadata.hermes.requires_tools") ?? []
        let fallbackToolsets = fields.list("fallback_for_toolsets") ?? fields.list("metadata.hermes.fallback_for_toolsets") ?? []
        let fallbackTools = fields.list("fallback_for_tools") ?? fields.list("metadata.hermes.fallback_for_tools") ?? []
        let relatedSkills = fields.list("related_skills") ?? fields.list("metadata.hermes.related_skills") ?? []

        return SkillDocument(
            title: title,
            description: description,
            category: category,
            triggerPatterns: triggers,
            provenance: SkillProvenance(source: .imported),
            tags: tags,
            trust: trust,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            platforms: platforms,
            workflowID: fields.scalar("workflow"),
            sourceDirectory: sourceDirectory,
            supportingFiles: supportingFiles,
            relatedSkills: relatedSkills,
            requiredToolsets: requiredToolsets,
            requiredTools: requiredTools,
            fallbackToolsets: fallbackToolsets,
            fallbackTools: fallbackTools,
            requiredEnvironmentVariables: fields.environmentRequirements,
            configRequirements: fields.configRequirements,
            pinned: fields.scalar("pinned") == "true"
        )
    }

    private func parseFields(_ source: String) -> ParsedFields {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var path: [String] = []
        var configRequirements: [SkillConfigRequirement] = []
        var environmentRequirements: [SkillEnvironmentRequirement] = []
        var currentConfig: [String: String] = [:]
        var currentEnv: [String: String] = [:]

        func flushConfig() {
            guard let key = currentConfig["key"] else { return }
            configRequirements.append(SkillConfigRequirement(
                key: key,
                description: currentConfig["description"],
                defaultValue: currentConfig["default"],
                prompt: currentConfig["prompt"],
                url: currentConfig["url"]
            ))
            currentConfig = [:]
        }

        func flushEnv() {
            guard let name = currentEnv["name"] else { return }
            environmentRequirements.append(SkillEnvironmentRequirement(
                name: name,
                prompt: currentEnv["prompt"],
                help: currentEnv["help"],
                requiredFor: currentEnv["required_for"]
            ))
            currentEnv = [:]
        }

        for raw in lines {
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let indent = raw.prefix { $0 == " " }.count
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            while path.count > indent / 2 { path.removeLast() }

            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2))
                if path.last == "config" {
                    flushConfig()
                    if let pair = parsePair(item) { currentConfig[pair.key] = pair.value }
                } else if path.last == "required_environment_variables" {
                    flushEnv()
                    if let pair = parsePair(item) { currentEnv[pair.key] = pair.value }
                }
                continue
            }

            guard let pair = parsePair(trimmed) else { continue }
            if pair.value.isEmpty {
                path.append(pair.key)
                continue
            }

            let dotted = (path + [pair.key]).joined(separator: ".")
            if path.last == "config" {
                currentConfig[pair.key] = pair.value
            } else if path.last == "required_environment_variables" {
                currentEnv[pair.key] = pair.value
            } else if pair.value.hasPrefix("[") && pair.value.hasSuffix("]") {
                lists[pair.key] = parseInlineList(pair.value)
                lists[dotted] = parseInlineList(pair.value)
            } else {
                scalars[pair.key] = pair.value
                scalars[dotted] = pair.value
            }
        }
        flushConfig()
        flushEnv()
        return ParsedFields(scalars: scalars, lists: lists, configRequirements: configRequirements, environmentRequirements: environmentRequirements)
    }

    private func parsePair(_ line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return (String(key), value)
    }

    private func parseInlineList(_ value: String) -> [String] {
        let inner = value.dropFirst().dropLast()
        return inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }.filter { !$0.isEmpty }
    }

    private func firstLineOf(_ body: String, fallback: String) -> String {
        body.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
            ?? fallback
    }
}

private struct ParsedFields: Sendable {
    var scalars: [String: String]
    var lists: [String: [String]]
    var configRequirements: [SkillConfigRequirement]
    var environmentRequirements: [SkillEnvironmentRequirement]

    func scalar(_ key: String) -> String? { scalars[key] }
    func list(_ key: String) -> [String]? { lists[key] }
}
