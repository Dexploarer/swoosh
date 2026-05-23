// SwooshCLI/CLIJSON.swift — Shared JSON encoder for CLI `--json` output — 0.4A
//
// Previously buried as a static extension on JSONEncoder inside
// ChatAdapterCommands.swift but used by plugin/skill/cron/terminal/etc.
// Centralising the helper avoids confusion about ownership and matches
// the rest of the CLI's convention of one-purpose-per-file.

import Foundation

extension JSONEncoder {
    /// Pretty-printed, sorted-keys, ISO-8601 encoder used by every CLI
    /// command that supports `--json` output.
    static var swooshCLI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
