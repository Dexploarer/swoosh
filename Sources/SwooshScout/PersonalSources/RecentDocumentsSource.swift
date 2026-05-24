// SwooshScout/PersonalSources/RecentDocumentsSource.swift — 0.9S Recent docs surface (macOS)
//
// Reads `~/Library/Application Support/com.apple.sharedfilelist/` —
// the on-disk equivalent of "File → Open Recent" across all apps.
// macOS-only. We surface per-app modification metadata (which app has
// recent docs, how recently the list was touched), never the individual
// bookmark-encoded document paths.

import Foundation

public struct RecentDocumentsSource: ScoutSource {
    public let id = "recent_documents"
    public let displayName = "Recent Documents"
    public let description = "Files surfaced by macOS's per-app Recent Documents lists."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["recent_documents.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if os(macOS)
        let dir = sharedFileListDirectory()
        return FileManager.default.fileExists(atPath: dir.path) ? .granted : .denied
        #else
        return .denied
        #endif
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        try await checkPermission()
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if os(macOS)
        let dir = sharedFileListDirectory()
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }

        // sharedfilelist files are bookmark-encoded blobs. Without a
        // full bookmark resolver we can still surface useful per-app
        // metadata: which apps the user has recent documents for, and
        // how recently each file list was modified.
        return children.compactMap { url -> ScoutRecord? in
            guard url.pathExtension == "sfl2" || url.pathExtension == "sfl3" else { return nil }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let modified = (attrs?[.modificationDate] as? Date) ?? .distantPast
            let appHint = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "com.apple.LSSharedFileList.RecentDocuments", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
                .scoutIfEmpty(else: "system")
            return ScoutRecord(
                sourceID: id, kind: .recentDocument, sensitivity: .medium,
                content: "Recent-documents list updated for \(appHint).",
                metadata: [
                    "list": url.lastPathComponent,
                    "modified": ISO8601DateFormatter().string(from: modified)
                ]
            )
        }
        #else
        return []
        #endif
    }

    #if os(macOS)
    private func sharedFileListDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist",
                                    isDirectory: true)
    }
    #endif
}

internal extension String {
    /// Returns the receiver, or `fallback` if the receiver is empty.
    /// File-internal helper used by `RecentDocumentsSource` and any
    /// future personal source that needs a sensible default for an
    /// app-hint-style derived name.
    func scoutIfEmpty(else fallback: String) -> String { isEmpty ? fallback : self }
}
