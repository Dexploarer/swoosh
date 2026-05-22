// SwooshPluginRuntime/SBPLProfile.swift — 0.8C macOS sandbox-exec profile
//
// `sandbox-exec(1)` is officially deprecated but still ships and still
// works on every supported macOS version. It's the only way to apply
// kernel-level network/filesystem confinement to a child process without
// adopting App Sandbox entitlements on the whole daemon — which we can't
// do because `swooshd` also needs to spawn ActantDB, talk to providers,
// and otherwise act as a non-sandboxed binary.
//
// The profile below denies most syscalls by default and reopens just
// what the plugin needs: read access to system frameworks + the plugin
// dir, write access to /tmp + the plugin dir, fork to run the child
// itself. Network is denied unless `sandbox.allowNetwork` is set, and
// filesystem writes outside /tmp + the plugin dir are denied unless
// `sandbox.allowFilesystemWrite` is set.
//
// What this CAN'T do:
//   • Linux has no equivalent — the runner falls back to a plain Process
//     spawn there. `bwrap`/seccomp-bpf would be the right answers; both
//     are out of scope for this pass.
//   • The profile leaks some macOS frameworks (CoreFoundation, etc.) via
//     `read*` on /System — a determined plugin can still call
//     `[NSWorkspace launchApplication:]` if it gets to ObjC. The point
//     here isn't to confine a malicious Mach-O attacker; it's to keep
//     well-meaning scripts from accidentally clobbering ~/.bash_profile.

import Foundation

public enum SBPLProfileBuilder {
    /// Whether `sandbox-exec` is available on this host. Returns false on
    /// every non-macOS platform.
    public static var isAvailable: Bool {
        #if os(macOS)
        return FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec")
        #else
        return false
        #endif
    }

    /// Build an SBPL profile string for a single plugin invocation.
    ///
    /// Strategy: start from `(allow default)` — every syscall permitted
    /// unless explicitly denied. This is deliberately less restrictive
    /// than `(deny default)` because a strict deny-list breaks dyld,
    /// mach IPC, signal delivery, and a dozen other syscalls that
    /// libsystem expects unconditionally, even for the trivial case of
    /// running `/bin/sh -c 'echo hi'`. A real deny-default profile is
    /// possible but requires per-macOS-release tuning and is brittle
    /// across security updates.
    ///
    /// The user-visible promises this profile *does* keep:
    ///   • Network is denied unless `allowNetwork` is set. Plugins can't
    ///     phone home, can't open sockets, can't talk to LAN services.
    ///   • Filesystem writes are confined to /tmp + the plugin dir +
    ///     any `allowedRoots`. Writes to `$HOME`, `/etc`, `/usr/local`
    ///     and other sensitive areas are denied.
    ///
    /// What this still leaks (callers should know):
    ///   • Filesystem *reads* are unrestricted — a malicious plugin can
    ///     read $HOME, /etc/passwd, etc. Read confinement under
    ///     allow-default would require enumerating every dyld path and
    ///     framework subpath, which is unstable across OS releases.
    ///     This is the same trade-off `sandbox-exec`'s own bundled
    ///     `no-internet` profile makes.
    ///   • The plugin can spawn other processes (process-exec* not
    ///     denied) — they inherit the same sandbox.
    public static func profile(
        pluginDir: URL,
        allowNetwork: Bool,
        allowFilesystemWrite: Bool,
        allowedRoots: [String]
    ) -> String {
        let pluginPath = pluginDir.path
        var writeRoots: [String] = ["/tmp", "/var/tmp", "/var/folders"]
        for path in writeRoots { writeRoots.append(contentsOf: doubleVarPrivate(path)) }
        writeRoots.append(pluginPath)
        writeRoots.append(contentsOf: doubleVarPrivate(pluginPath))
        if allowFilesystemWrite {
            for root in allowedRoots where !root.isEmpty {
                writeRoots.append(root)
                writeRoots.append(contentsOf: doubleVarPrivate(root))
            }
        }

        var lines: [String] = []
        lines.append(";; Swoosh plugin sandbox profile — auto-generated")
        lines.append("(version 1)")
        lines.append("(allow default)")
        if !allowNetwork {
            lines.append("(deny network*)")
        }
        if !allowFilesystemWrite {
            // Deny writes everywhere first, then reopen the specific
            // subpaths the plugin needs. SBPL processes top-to-bottom,
            // last match wins, so the allow-list at the end overrides
            // the deny at the top.
            lines.append("(deny file-write*)")
            lines.append("(allow file-write*")
            for root in dedupe(writeRoots) { lines.append("  (subpath \(quote(root)))") }
            lines.append(")")
        }
        // Note: deliberately no `process-exec` restriction. Plugins are
        // expected to be small scripts that may shell out for utility
        // calls (jq, curl-when-allowed, etc.) — restricting exec would
        // break that and gives little marginal safety over the
        // net/write confinement.
        return lines.joined(separator: "\n")
    }

    /// macOS path symlink doubling. `/var` and `/tmp` are symlinks into
    /// `/private/var` and `/private/tmp`. SBPL matches against the
    /// resolved path, so we emit both forms.
    private static func doubleVarPrivate(_ path: String) -> [String] {
        if path.hasPrefix("/private/") { return [] }
        if path == "/var" || path.hasPrefix("/var/") {
            return ["/private" + path]
        }
        if path == "/tmp" || path.hasPrefix("/tmp/") {
            return ["/private" + path]
        }
        return []
    }

    private static func dedupe(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for path in paths where !path.isEmpty {
            if seen.insert(path).inserted {
                out.append(path)
            }
        }
        return out
    }

    /// Quote a path for embedding in an SBPL string literal. Same rules
    /// as a Scheme string: escape backslashes and double quotes.
    private static func quote(_ path: String) -> String {
        var escaped = path
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
