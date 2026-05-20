// SwooshCLI/SkillCommands.swift — Install and manage skills
import ArgumentParser
import Foundation
import SwooshSkills

struct SkillsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "List, inspect, install, and approve skills.",
        subcommands: [
            SkillsListCommand.self,
            SkillsGetCommand.self,
            SkillsSearchCommand.self,
            SkillsInstallCommand.self,
            SkillsApproveCommand.self,
            SkillsDeleteCommand.self,
        ],
        defaultSubcommand: SkillsListCommand.self
    )
}

struct SkillsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List installed skills.")

    @Flag(name: .long, help: "Include draft and rejected skills.")
    var all = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let skills = try await skillStore().listAll()
            .filter { all || SkillTrust.promptable.contains($0.trust) }
        if json {
            let data = try JSONEncoder.swooshCLI.encode(skills)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }
        for skill in skills {
            print("\(skill.id.padding(toLength: 30, withPad: " ", startingAt: 0)) \(skill.trust.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(skill.title)")
        }
    }
}

struct SkillsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Print a skill body or support file.")

    @Argument(help: "Skill id.")
    var id: String

    @Option(name: .long, help: "Relative support-file path.")
    var file: String?

    func run() async throws {
        let store = skillStore()
        guard let skill = try await store.get(id: id) else {
            throw ValidationError("Skill not found: \(id)")
        }
        if let file {
            guard let sourceDirectory = skill.sourceDirectory else {
                throw ValidationError("Skill has no support-file directory: \(id)")
            }
            print(try readSkillSupportFile(file, sourceDirectory: sourceDirectory))
            return
        }
        print(skill.body)
    }
}

struct SkillsSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Search installed skills.")

    @Argument(help: "Search query.")
    var query: String

    @Option(name: .long, help: "Maximum results.")
    var limit = 10

    func run() async throws {
        let matches = try await skillStore().search(query: query, limit: limit)
        for skill in matches {
            print("\(skill.id.padding(toLength: 30, withPad: " ", startingAt: 0)) \(skill.trust.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(skill.title)")
        }
    }
}

struct SkillsInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install a skill from a local path, URL, or github:owner/repo/path.")

    @Argument(help: "Skill source.")
    var source: String

    @Option(name: .long, help: "Override installed skill name.")
    var name: String?

    @Option(name: .long, help: "Initial trust: draft, reviewed, or promoted.")
    var trust = "reviewed"

    func run() async throws {
        guard let installTrust = SkillInstallTrust(rawValue: trust) else {
            throw ValidationError("Invalid trust '\(trust)'. Use draft, reviewed, or promoted.")
        }
        let installer = SkillInstaller(store: skillStore())
        let result = try await installer.install(source: source, name: name, trust: installTrust)
        print("Installed \(result.id) — \(result.title) (\(result.trust.rawValue))")
        for warning in result.warnings {
            print("warning: \(warning)")
        }
    }
}

struct SkillsApproveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "approve", abstract: "Promote or reject a skill.")

    @Argument(help: "Skill id.")
    var id: String

    @Option(name: .long, help: "Trust value: reviewed, promoted, frozen, rejected, or draft.")
    var trust = "promoted"

    func run() async throws {
        guard let nextTrust = SkillTrust(rawValue: trust) else {
            throw ValidationError("Invalid trust '\(trust)'.")
        }
        let store = skillStore()
        guard var skill = try await store.get(id: id) else {
            throw ValidationError("Skill not found: \(id)")
        }
        skill.trust = nextTrust
        try await store.update(skill)
        print("Updated \(id) to \(nextTrust.rawValue).")
    }
}

struct SkillsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an unpinned skill.")

    @Argument(help: "Skill id.")
    var id: String

    func run() async throws {
        let store = skillStore()
        guard let skill = try await store.get(id: id) else {
            throw ValidationError("Skill not found: \(id)")
        }
        guard !skill.pinned else {
            throw ValidationError("Skill is pinned and cannot be deleted: \(id)")
        }
        try await store.delete(id: id)
        print("Deleted \(id).")
    }
}

private func skillStore() -> FileSkillStore {
    FileSkillStore()
}

private func readSkillSupportFile(_ path: String, sourceDirectory: String) throws -> String {
    guard !path.hasPrefix("/") && !path.split(separator: "/").contains("..") else {
        throw ValidationError("Invalid support-file path: \(path)")
    }
    let root = URL(fileURLWithPath: sourceDirectory, isDirectory: true).standardizedFileURL
    let url = root.appendingPathComponent(path).standardizedFileURL
    guard url.path.hasPrefix(root.path + "/") else {
        throw ValidationError("Invalid support-file path: \(path)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}
