// SwooshToolsets/TerminalTools.swift — Terminal backend registry and execution
import Foundation
import SwooshTools

public enum TerminalBackend: String, Codable, Sendable, CaseIterable {
    case local
    case docker
    case ssh
    case singularity
    case modal
    case daytona
    case vercelSandbox
}

public struct TerminalBackendStatus: Codable, Sendable {
    public let backend: TerminalBackend
    public let available: Bool
    public let configured: Bool
    public let detail: String
}

public struct TerminalConfig: Codable, Sendable {
    public var backend: TerminalBackend
    public var cwd: String?
    public var timeoutSeconds: Int
    public var dockerImage: String
    public var containerPersistent: Bool
    public var containerName: String?
    public var sshHost: String?
    public var sshUser: String?
    public var sshKeyPath: String?
    public var singularityImage: String?
    public var modalImage: String?
    public var daytonaImage: String?
    public var vercelRuntime: String?

    public static let defaults = TerminalConfig(
        backend: .local,
        cwd: nil,
        timeoutSeconds: 180,
        dockerImage: "nikolaik/python-nodejs:python3.11-nodejs20",
        containerPersistent: true,
        containerName: nil,
        sshHost: nil,
        sshUser: nil,
        sshKeyPath: nil,
        singularityImage: nil,
        modalImage: nil,
        daytonaImage: nil,
        vercelRuntime: nil
    )
}

public struct TerminalBackendsInput: Codable, Sendable {
    public init() {}
}

public struct TerminalBackendsOutput: Codable, Sendable {
    public let active: TerminalBackend
    public let config: TerminalConfig
    public let backends: [TerminalBackendStatus]
}

public struct TerminalConfigureInput: Codable, Sendable {
    public let backend: TerminalBackend
    public let cwd: String?
    public let dockerImage: String?
    public let containerPersistent: Bool?
    public let sshHost: String?
    public let sshUser: String?
    public let sshKeyPath: String?
    public let singularityImage: String?
    public let modalImage: String?
    public let daytonaImage: String?
    public let vercelRuntime: String?

    public init(
        backend: TerminalBackend,
        cwd: String? = nil,
        dockerImage: String? = nil,
        containerPersistent: Bool? = nil,
        sshHost: String? = nil,
        sshUser: String? = nil,
        sshKeyPath: String? = nil,
        singularityImage: String? = nil,
        modalImage: String? = nil,
        daytonaImage: String? = nil,
        vercelRuntime: String? = nil
    ) {
        self.backend = backend
        self.cwd = cwd
        self.dockerImage = dockerImage
        self.containerPersistent = containerPersistent
        self.sshHost = sshHost
        self.sshUser = sshUser
        self.sshKeyPath = sshKeyPath
        self.singularityImage = singularityImage
        self.modalImage = modalImage
        self.daytonaImage = daytonaImage
        self.vercelRuntime = vercelRuntime
    }
}

public struct TerminalConfigureOutput: Codable, Sendable {
    public let config: TerminalConfig
}

public struct TerminalRunInput: Codable, Sendable {
    public let command: String
    public let backend: TerminalBackend?
    public let workingDirectory: String?
    public let environment: [String: String]?

    public init(command: String, backend: TerminalBackend? = nil, workingDirectory: String? = nil, environment: [String: String]? = nil) {
        self.command = command
        self.backend = backend
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public struct TerminalRunOutput: Codable, Sendable {
    public let backend: TerminalBackend
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let workingDirectory: String
}

public actor TerminalConfigStore {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/terminal.json")
    }

    public func load() throws -> TerminalConfig {
        if let env = ProcessInfo.processInfo.environment["TERMINAL_ENV"], let backend = TerminalBackend(envValue: env) {
            var config = try loadPersisted()
            config.backend = backend
            return config.withEnvironmentOverrides()
        }
        return try loadPersisted().withEnvironmentOverrides()
    }

    public func save(_ config: TerminalConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    private func loadPersisted() throws -> TerminalConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TerminalConfig.self, from: data)
    }
}

public struct TerminalBackendsTool: SwooshTool {
    public typealias Input = TerminalBackendsInput
    public typealias Output = TerminalBackendsOutput
    public static let name: ToolName = "terminal.backends"
    public static let displayName = "Terminal Backends"
    public static let description = "List terminal execution backends and their configuration status."
    public static let permission = SwooshPermission.shellRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.terminal
    let dependencies: ToolDependencies
    let store: TerminalConfigStore
    public init(dependencies: ToolDependencies, store: TerminalConfigStore = TerminalConfigStore()) {
        self.dependencies = dependencies
        self.store = store
    }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let config = try await store.load()
        return TerminalBackendsOutput(active: config.backend, config: config, backends: TerminalBackend.allCases.map { terminalBackendStatus(for: $0, config: config) })
    }
}

public struct TerminalConfigureTool: SwooshTool {
    public typealias Input = TerminalConfigureInput
    public typealias Output = TerminalConfigureOutput
    public static let name: ToolName = "terminal.configure"
    public static let displayName = "Configure Terminal"
    public static let description = "Set the default terminal backend for agent shell execution."
    public static let permission = SwooshPermission.toolWrite
    public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.humanOnly
    public static let toolset = ToolsetID.terminal
    let dependencies: ToolDependencies
    let store: TerminalConfigStore
    public init(dependencies: ToolDependencies, store: TerminalConfigStore = TerminalConfigStore()) {
        self.dependencies = dependencies
        self.store = store
    }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        var config = try await store.load()
        config.backend = input.backend
        if let cwd = input.cwd { config.cwd = cwd }
        if let dockerImage = input.dockerImage { config.dockerImage = dockerImage }
        if let containerPersistent = input.containerPersistent { config.containerPersistent = containerPersistent }
        if let sshHost = input.sshHost { config.sshHost = sshHost }
        if let sshUser = input.sshUser { config.sshUser = sshUser }
        if let sshKeyPath = input.sshKeyPath { config.sshKeyPath = sshKeyPath }
        if let singularityImage = input.singularityImage { config.singularityImage = singularityImage }
        if let modalImage = input.modalImage { config.modalImage = modalImage }
        if let daytonaImage = input.daytonaImage { config.daytonaImage = daytonaImage }
        if let vercelRuntime = input.vercelRuntime { config.vercelRuntime = vercelRuntime }
        try await store.save(config)
        return TerminalConfigureOutput(config: config)
    }
}

public struct TerminalRunTool: SwooshTool {
    public typealias Input = TerminalRunInput
    public typealias Output = TerminalRunOutput
    public static let name: ToolName = "terminal.run"
    public static let displayName = "Run Terminal Command"
    public static let description = "Execute a command through the configured terminal backend."
    public static let permission = SwooshPermission.shellRun
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.terminal
    let dependencies: ToolDependencies
    let store: TerminalConfigStore
    public init(dependencies: ToolDependencies, store: TerminalConfigStore = TerminalConfigStore()) {
        self.dependencies = dependencies
        self.store = store
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        var config = try await store.load()
        if let backend = input.backend { config.backend = backend }
        let cwdPath = input.workingDirectory ?? config.cwd ?? FileManager.default.currentDirectoryPath
        let cwd = URL(fileURLWithPath: NSString(string: cwdPath).expandingTildeInPath, isDirectory: true)
        let env = input.environment
        let result: ProcessResult
        switch config.backend {
        case .local:
            result = try await runLocal(input.command, cwd: cwd, environment: env)
        case .docker:
            result = try await runDocker(input.command, cwd: cwd, config: config)
        case .ssh:
            result = try await runSSH(input.command, cwd: cwd, config: config)
        case .singularity:
            result = try await runSingularity(input.command, cwd: cwd, config: config)
        case .modal, .daytona, .vercelSandbox:
            throw ToolError.executionFailed("\(config.backend.rawValue) backend is configurable but requires its provider CLI/API bridge before command execution.")
        }
        return TerminalRunOutput(backend: config.backend, exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, workingDirectory: cwd.path)
    }

    private func runLocal(_ command: String, cwd: URL, environment: [String: String]?) async throws -> ProcessResult {
        let parsed = try parseCommand(command)
        return try await dependencies.processRunner.run(
            executable: parsed.executable,
            arguments: parsed.arguments,
            workingDirectory: cwd,
            environment: environment
        )
    }

    private func runDocker(_ command: String, cwd: URL, config: TerminalConfig) async throws -> ProcessResult {
        let docker = try dockerBinary()
        let image = config.dockerImage
        if config.containerPersistent {
            let name = config.containerName ?? "swoosh-terminal-\(safeName(ProcessInfo.processInfo.globallyUniqueString))"
            let inspect = try await dependencies.processRunner.run(executable: docker, arguments: ["inspect", "-f", "{{.State.Running}}", name], workingDirectory: nil, environment: nil)
            if inspect.exitCode != 0 || !inspect.stdout.contains("true") {
                _ = try await dependencies.processRunner.run(executable: docker, arguments: ["rm", "-f", name], workingDirectory: nil, environment: nil)
                let start = try await dependencies.processRunner.run(
                    executable: docker,
                    arguments: ["run", "-d", "--name", name, "-v", "\(cwd.path):/workspace", "-w", "/workspace", image, "sleep", "7200"],
                    workingDirectory: nil,
                    environment: nil
                )
                guard start.exitCode == 0 else { return start }
            }
            return try await dependencies.processRunner.run(executable: docker, arguments: ["exec", "-w", "/workspace", name, "/bin/sh", "-lc", command], workingDirectory: nil, environment: nil)
        }
        return try await dependencies.processRunner.run(
            executable: docker,
            arguments: ["run", "--rm", "-v", "\(cwd.path):/workspace", "-w", "/workspace", image, "/bin/sh", "-lc", command],
            workingDirectory: nil,
            environment: nil
        )
    }

    private func runSSH(_ command: String, cwd: URL, config: TerminalConfig) async throws -> ProcessResult {
        let host = config.sshHost ?? ProcessInfo.processInfo.environment["TERMINAL_SSH_HOST"]
        let user = config.sshUser ?? ProcessInfo.processInfo.environment["TERMINAL_SSH_USER"]
        guard let host, let user else { throw ToolError.executionFailed("ssh backend requires TERMINAL_SSH_HOST and TERMINAL_SSH_USER or saved config") }
        var args: [String] = []
        let key = config.sshKeyPath ?? ProcessInfo.processInfo.environment["TERMINAL_SSH_KEY"]
        if let key { args += ["-i", NSString(string: key).expandingTildeInPath] }
        args += ["\(user)@\(host)", "cd \(shellQuote(cwd.path)) && \(command)"]
        return try await dependencies.processRunner.run(executable: "/usr/bin/ssh", arguments: args, workingDirectory: nil, environment: nil)
    }

    private func runSingularity(_ command: String, cwd: URL, config: TerminalConfig) async throws -> ProcessResult {
        guard let image = config.singularityImage ?? ProcessInfo.processInfo.environment["TERMINAL_SINGULARITY_IMAGE"] else {
            throw ToolError.executionFailed("singularity backend requires TERMINAL_SINGULARITY_IMAGE or saved config")
        }
        let binary = resolveExecutable("apptainer") ?? resolveExecutable("singularity")
        guard let binary else { throw ToolError.executionFailed("apptainer or singularity is not on PATH") }
        return try await dependencies.processRunner.run(
            executable: binary,
            arguments: ["exec", "--containall", "--pwd", cwd.path, NSString(string: image).expandingTildeInPath, "/bin/sh", "-lc", command],
            workingDirectory: cwd,
            environment: nil
        )
    }
}

private struct ParsedCommand {
    let executable: String
    let arguments: [String]
}

private func parseCommand(_ raw: String) throws -> ParsedCommand {
    var tokens: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    for char in raw {
        if escaping {
            current.append(char)
            escaping = false
            continue
        }
        if char == "\\" {
            escaping = true
            continue
        }
        if let active = quote {
            if char == active {
                quote = nil
            } else {
                current.append(char)
            }
            continue
        }
        if char == "'" || char == "\"" {
            quote = char
            continue
        }
        if char.isWhitespace {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            continue
        }
        current.append(char)
    }

    guard quote == nil else {
        throw ToolError.invalidInput("unterminated quote in terminal command")
    }
    guard !escaping else {
        throw ToolError.invalidInput("dangling escape in terminal command")
    }
    if !current.isEmpty {
        tokens.append(current)
    }
    guard let executable = tokens.first else {
        throw ToolError.invalidInput("terminal command is empty")
    }
    return ParsedCommand(executable: executable, arguments: Array(tokens.dropFirst()))
}

private extension TerminalBackend {
    init?(envValue: String) {
        switch envValue {
        case "local": self = .local
        case "docker": self = .docker
        case "ssh": self = .ssh
        case "singularity": self = .singularity
        case "modal": self = .modal
        case "daytona": self = .daytona
        case "vercel_sandbox", "vercelSandbox": self = .vercelSandbox
        default: return nil
        }
    }
}

private extension TerminalConfig {
    func withEnvironmentOverrides() -> TerminalConfig {
        var copy = self
        let env = ProcessInfo.processInfo.environment
        if let cwd = env["TERMINAL_CWD"] { copy.cwd = cwd }
        if let timeout = env["TERMINAL_TIMEOUT"].flatMap(Int.init) { copy.timeoutSeconds = timeout }
        if let image = env["TERMINAL_DOCKER_IMAGE"] { copy.dockerImage = image }
        if let image = env["TERMINAL_SINGULARITY_IMAGE"] { copy.singularityImage = image }
        if let image = env["TERMINAL_MODAL_IMAGE"] { copy.modalImage = image }
        if let image = env["TERMINAL_DAYTONA_IMAGE"] { copy.daytonaImage = image }
        if let runtime = env["TERMINAL_VERCEL_RUNTIME"] { copy.vercelRuntime = runtime }
        if let host = env["TERMINAL_SSH_HOST"] { copy.sshHost = host }
        if let user = env["TERMINAL_SSH_USER"] { copy.sshUser = user }
        if let key = env["TERMINAL_SSH_KEY"] { copy.sshKeyPath = key }
        return copy
    }
}

public func terminalBackendStatus(for backend: TerminalBackend, config: TerminalConfig) -> TerminalBackendStatus {
    switch backend {
    case .local:
        return TerminalBackendStatus(backend: backend, available: true, configured: true, detail: "host allowlist")
    case .docker:
        let bin = resolveExecutable(ProcessInfo.processInfo.environment["HERMES_DOCKER_BINARY"] ?? "docker") ?? resolveExecutable("podman")
        return TerminalBackendStatus(backend: backend, available: bin != nil, configured: !config.dockerImage.isEmpty, detail: bin ?? "docker/podman missing")
    case .ssh:
        let configured = (config.sshHost ?? ProcessInfo.processInfo.environment["TERMINAL_SSH_HOST"]) != nil &&
            (config.sshUser ?? ProcessInfo.processInfo.environment["TERMINAL_SSH_USER"]) != nil
        return TerminalBackendStatus(backend: backend, available: FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh"), configured: configured, detail: configured ? "ssh target configured" : "missing host/user")
    case .singularity:
        let bin = resolveExecutable("apptainer") ?? resolveExecutable("singularity")
        let configured = (config.singularityImage ?? ProcessInfo.processInfo.environment["TERMINAL_SINGULARITY_IMAGE"]) != nil
        return TerminalBackendStatus(backend: backend, available: bin != nil, configured: configured, detail: bin ?? "apptainer/singularity missing")
    case .modal:
        return TerminalBackendStatus(backend: backend, available: resolveExecutable("modal") != nil, configured: (config.modalImage ?? ProcessInfo.processInfo.environment["TERMINAL_MODAL_IMAGE"]) != nil, detail: "requires Modal CLI bridge")
    case .daytona:
        return TerminalBackendStatus(backend: backend, available: ProcessInfo.processInfo.environment["DAYTONA_API_KEY"] != nil, configured: true, detail: "requires Daytona API bridge")
    case .vercelSandbox:
        let configured = ProcessInfo.processInfo.environment["VERCEL_TOKEN"] != nil || ProcessInfo.processInfo.environment["VERCEL_OIDC_TOKEN"] != nil
        return TerminalBackendStatus(backend: backend, available: configured, configured: configured, detail: configured ? "Vercel auth present" : "missing Vercel auth")
    }
}

private func dockerBinary() throws -> String {
    if let override = ProcessInfo.processInfo.environment["HERMES_DOCKER_BINARY"] {
        return override
    }
    if let docker = resolveExecutable("docker") { return docker }
    if let podman = resolveExecutable("podman") { return podman }
    throw ToolError.executionFailed("docker or podman is not on PATH")
}

private func resolveExecutable(_ name: String) -> String? {
    if name.hasPrefix("/") {
        return FileManager.default.isExecutableFile(atPath: name) ? name : nil
    }
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin")
        .split(separator: ":")
        .map(String.init)
    for path in paths {
        let candidate = URL(fileURLWithPath: path).appendingPathComponent(name).path
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
}

private func safeName(_ raw: String) -> String {
    raw.lowercased()
        .unicodeScalars
        .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        .reduce(into: "") { $0.append($1) }
}

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
