// SwooshCLIRunner/main.swift — Thin executable entrypoint — 0.4B
//
// All command logic lives in the `SwooshCLI` library target so tests can
// `@testable import SwooshCLI` against the real `AsyncParsableCommand`
// types. `@main` here (rather than top-level await) is required by
// swift-argument-parser, which expects an availability-annotated entry
// when the root command is async.

import SwooshCLI

@main
@available(macOS 10.15, *)
struct SwooshCLIMain {
    static func main() async {
        await SwooshCommand.main()
    }
}
