// SwooshProviders/CodexBridgeProvider.swift — 1.0C OpenAI Codex CLI bridge
//
// Uses the locally-installed `codex` CLI as the inference backend so the
// user's ChatGPT Plus/Pro subscription pays for tokens. We invoke
// `codex exec` once per chat turn, read the last assistant message from a
// temp file, and return it as a `ModelResponse`.
//
// Codex is fundamentally an *agent* — it has its own internal tool loop,
// sandbox, and reasoning model. We deliberately conform only to
// `ModelProviding` (not `ToolCallingModelProviding`): when Codex is the
// active provider, swooshd's tool registry is dormant for that turn —
// Codex does any tool work internally in its read-only sandbox.
//
// Auth: we never touch `~/.codex/auth.json` directly. `codex login status`
// is our single source of truth. The daemon exposes `/api/codex/auth/...`
// endpoints (see SwooshAPI) that spawn `codex login` interactively when
// the user taps "Sign in with ChatGPT".
//
// Per-call overrides (intentional — never touch the user's config.toml):
//   --skip-git-repo-check   — Swoosh's cwd is ~/.swoosh, not a git repo.
//   --ephemeral             — don't pile up session files.
//   -s read-only            — codex cannot side-effect the filesystem.
//   --color never           — clean text output.
//   -c model_reasoning_effort="minimal"  — chat shouldn't wait 60s.
//   -c approval_policy="never"           — no interactive prompts.
//   -C <swooshDir>          — stable non-repo cwd.
//   -o <tmpfile>            — last assistant message lands here.
//   stdin                   — prompt is fed via stdin (handles long history).

import Foundation
import SwooshTools

#if os(macOS) || os(Linux)

public actor CodexBridgeProvider: ModelProviding {
    public nonisolated let providerID: ProviderID = "codex"
    public nonisolated let displayName: String = "ChatGPT (via Codex)"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: false, toolCalling: false,
        structuredOutput: false, embeddings: false, vision: false
    )

    /// Path to the `codex` executable. Resolved at init; nil means not installed.
    private let codexBinary: URL?
    /// Working directory for `codex exec -C`. Should NOT be a git repo —
    /// Swoosh's data dir is the canonical choice.
    private let workingDirectory: URL
    /// Hard ceiling on a single chat turn. ChatGPT can take a while with
    /// reasoning even at "minimal" effort; 120s is generous.
    private let timeoutSeconds: TimeInterval

    public init(workingDirectory: URL? = nil, timeoutSeconds: TimeInterval = 120) {
        self.codexBinary = Self.findCodex()
        self.workingDirectory = workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".swoosh", isDirectory: true)
        self.timeoutSeconds = timeoutSeconds
    }

    // ── Public API ────────────────────────────────────────────────

    /// Returns `true` if `codex login status` reports an authenticated session.
    /// Cheap enough to call on every detect pass.
    public func isAuthenticated() async -> Bool {
        guard let codex = codexBinary else { return false }
        let result = (try? await runProcess(
            executable: codex,
            arguments: ["login", "status"],
            stdin: nil,
            timeout: 5
        )) ?? ProcessResult(exitCode: -1, stdout: "", stderr: "")
        // codex login status prints "Logged in using ..." on success;
        // "Not logged in" on failure. Match the explicit string rather
        // than relying on exit code (which is 0 in both cases). When
        // invoked as a child Process (no controlling TTY), codex writes
        // the status to stderr — so check both streams.
        return result.stdout.contains("Logged in") || result.stderr.contains("Logged in")
    }

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        guard let codex = codexBinary else {
            throw ProviderError.authMissing(providerID,
                "codex CLI not installed. Install via `npm i -g @openai/codex`.")
        }
        guard await isAuthenticated() else {
            throw ProviderError.authMissing(providerID,
                "Codex is not signed in. Tap \"Sign in with ChatGPT\" in Swoosh Settings to start the OAuth flow.")
        }

        // Make sure the working dir exists — codex bails if -C is missing.
        try? FileManager.default.createDirectory(
            at: workingDirectory, withIntermediateDirectories: true)

        let prompt = renderPrompt(messages: request.messages,
                                  instructions: request.instructions)

        // Per-call output file — codex writes the final assistant message here.
        let tmpOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-out-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpOut) }

        var args: [String] = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "-s", "read-only",
            "--color", "never",
            "-c", "approval_policy=\"never\"",
            // OpenAI rejects "minimal" reasoning effort when codex has any
            // tools enabled (web_search, fs, etc.) — 400 invalid_request_error.
            // "low" is the next-tier-up that allows tools; still fast enough
            // for chat turns and doesn't depend on the user's codex config.
            "-c", "model_reasoning_effort=\"low\"",
            "-C", workingDirectory.path,
            "-o", tmpOut.path,
            "-"   // read prompt from stdin
        ]
        // Model override only if caller specified a real model (not "auto").
        if !request.model.isEmpty, request.model != "auto" {
            args.insert(contentsOf: ["-m", request.model], at: 1)
        }

        let started = Date()
        let result = try await runProcess(
            executable: codex,
            arguments: args,
            stdin: prompt,
            timeout: timeoutSeconds
        )

        if result.exitCode != 0 {
            let summary = result.stderr.isEmpty ? result.stdout : result.stderr
            let snippet = String(summary.prefix(400))
            throw ProviderError.requestFailed(providerID,
                "codex exit \(result.exitCode): \(snippet)")
        }

        let text: String
        if let body = try? String(contentsOf: tmpOut, encoding: .utf8),
           !body.isEmpty {
            text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Fallback: scrape stdout. codex prints the final message after
            // structured event lines; rather than parse the protocol, just
            // take whatever non-empty content arrived.
            text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !text.isEmpty else {
            throw ProviderError.responseParseFailed(providerID,
                "codex produced no output after \(Int(Date().timeIntervalSince(started)))s")
        }

        return ModelResponse(
            providerID: providerID,
            model: request.model.isEmpty ? "codex-default" : request.model,
            text: text,
            toolCalls: [],
            finishReason: "stop",
            usage: nil
        )
    }

    // ── Helpers ───────────────────────────────────────────────────

    private nonisolated func renderPrompt(messages: [ChatMessage],
                                          instructions: String?) -> String {
        var lines: [String] = []
        if let instructions, !instructions.isEmpty {
            lines.append("[Instructions]")
            lines.append(instructions)
            lines.append("")
        }
        // Cap history at the last 20 turns so we don't blow past the
        // model's context budget on very long sessions.
        let history = messages.suffix(20)
        for msg in history {
            let tag: String
            switch msg.role {
            case .system:    tag = "SYSTEM"
            case .developer: tag = "DEVELOPER"
            case .user:      tag = "USER"
            case .assistant: tag = "ASSISTANT"
            case .tool:      tag = "TOOL"
            }
            lines.append("\(tag): \(msg.content)")
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func findCodex() -> URL? {
        // Common locations on macOS — PATH lookup via Process is unreliable
        // when launched from launchd or Xcode, so probe explicit paths.
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.bun/bin/codex",
            "\(NSHomeDirectory())/.npm-global/bin/codex"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Process runner

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private nonisolated func runProcess(
        executable: URL,
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        try process.run()

        // Feed stdin (if any) then close so codex sees EOF.
        if let stdin {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
        }
        try? stdinPipe.fileHandleForWriting.close()

        // Hard timeout via a sibling Task.
        let timeoutTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(nanoseconds: 500_000_000)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        timeoutTask.cancel()

        let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

#else

/// iOS stub. The phone never talks to `codex` directly — it goes through
/// swooshd on the Mac. Compile-only placeholder so cross-platform call
/// sites in `ProviderBridge` and `Daemon` don't need their own `#if`s.
public actor CodexBridgeProvider: ModelProviding {
    public nonisolated let providerID: ProviderID = "codex"
    public nonisolated let displayName: String = "ChatGPT (via Codex)"
    public nonisolated let capabilities = ProviderCapabilities()

    public init(workingDirectory: URL? = nil, timeoutSeconds: TimeInterval = 120) {}

    public func isAuthenticated() async -> Bool { false }

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        throw ProviderError.authMissing(providerID,
            "Codex bridge is not available on this platform.")
    }
}

#endif
