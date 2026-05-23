// SwooshFiles/SafePathResolver.swift — Path resolver with escape prevention (0.4D)
//
// Every file tool uses this before any I/O.
// Rejects absolute paths, parent traversal, and escape attempts.

import Foundation

public struct SafePathResolver: Sendable {
    public init() {}

    /// Resolve a relative path within an approved root.
    /// Throws on any attempt to escape the root boundary.
    public func resolve(
        root: ApprovedRoot,
        relativePath: String
    ) throws -> URL {
        // 1. Reject absolute paths
        guard !relativePath.hasPrefix("/") else {
            throw FileAccessError.absolutePathNotAllowed
        }

        // 2. Reject parent traversal
        guard !relativePath.contains("..") else {
            throw FileAccessError.parentTraversalNotAllowed
        }

        // 3. Build candidate URL
        let rootURL = URL(fileURLWithPath: root.absolutePath).standardizedFileURL
        let candidate = rootURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        // 4. Verify candidate stays inside root
        guard candidate.path.hasPrefix(rootURL.path + "/") || candidate.path == rootURL.path else {
            throw FileAccessError.pathEscapesApprovedRoot
        }

        return candidate
    }

    /// Validate that a root allows the requested operation.
    public func validateAccess(root: ApprovedRoot, write: Bool) throws {
        guard root.allowedRead else {
            throw FileAccessError.readNotAllowed
        }
        if write && !root.allowedWrite {
            throw FileAccessError.writeNotAllowed
        }
    }
}

// MARK: - File access errors

public enum FileAccessError: Error, Sendable, Equatable {
    case absolutePathNotAllowed
    case parentTraversalNotAllowed
    case pathEscapesApprovedRoot
    case rootNotApproved
    case readNotAllowed
    case writeNotAllowed
    case sensitiveFileBlocked(String)
    case fileTooLarge(Int64)
    case unsupportedEncoding
    /// Returned by `deleteFile`. Distinct from `writeNotAllowed` so a UI
    /// can tell "this root is read-only" from "delete is globally off".
    case deletionUnsupported
    /// Returned by `resolveBookmark` when the stored bookmark data is
    /// stale (the underlying file moved or was deleted).
    case staleBookmark
}
