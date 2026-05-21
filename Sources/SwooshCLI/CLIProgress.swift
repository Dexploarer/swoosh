// SwooshCLI/CLIProgress.swift — Simple terminal progress bar

import Foundation

/// A simple progress bar for long-running CLI operations.
///
/// Usage when the total is known up front:
///   let bar = CLIProgress(total: sources.count, label: "Scanning")
///   for (index, source) in sources.enumerated() {
///       bar.update(step: index + 1, detail: source.name)
///   }
///   bar.finish()
///
/// Usage when the total is only known after the first progress event
/// (deferred-total pattern):
///   let bar = CLIProgress(total: 0, label: "Scanning")
///   // ... inside the progress callback:
///   if bar.total == 0 { bar.total = receivedTotal }
///   bar.update(step: current, detail: name)
///
/// While `total <= 0` the bar renders in an indeterminate style (just the
/// step count + detail, no percentage). Once a positive total is assigned,
/// subsequent updates draw the full bar.
///
/// Reference type so it can be captured and mutated across `@Sendable`
/// progress callbacks. Sendable conformance is unchecked because all
/// mutations are required to happen on the main thread — the call sites
/// (CLI subcommands) drive updates from a single concurrency domain.
public final class CLIProgress: @unchecked Sendable {
    /// The total number of steps. Settable so callers can supply the value
    /// after the first progress callback when the total isn't known at
    /// construction time. While `total <= 0`, updates render indeterminate.
    public var total: Int
    private let label: String
    private let width: Int
    private var lastLineLength: Int = 0

    public init(total: Int, label: String = "Progress", width: Int = 40) {
        self.total = total
        self.label = label
        self.width = width
    }

    /// Update the progress bar. Call from the main thread only.
    public func update(step: Int, detail: String? = nil) {
        let line: String
        if total > 0 {
            let pct = min(Double(step) / Double(total), 1.0)
            let filled = Int(pct * Double(width))
            let empty = width - filled
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
            let percent = Int(pct * 100)
            var s = "\(label) [\(bar)] \(percent)% (\(step)/\(total))"
            if let detail = detail, !detail.isEmpty {
                s += " — \(detail.prefix(30))"
            }
            line = s
        } else {
            // Indeterminate — total not yet known.
            var s = "\(label): \(step)"
            if let detail = detail, !detail.isEmpty {
                s += " — \(detail.prefix(30))"
            }
            line = s
        }

        // Clear previous line if it was longer
        if lastLineLength > line.count {
            let clear = String(repeating: " ", count: lastLineLength)
            print("\r\(clear)\r", terminator: "")
        } else {
            print("\r", terminator: "")
        }
        print(line, terminator: "")
        fflush(stdout)
        lastLineLength = line.count
    }

    /// Call when done to emit a newline.
    public func finish(message: String? = nil) {
        if let message = message {
            print("  ✓ \(message)")
        } else {
            print("")
        }
    }
}
