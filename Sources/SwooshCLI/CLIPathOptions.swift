// SwooshCLI/CLIPathOptions.swift — Shared CLI path option helpers (0.9P)

import Foundation
import SwooshConfig

func makeSwooshConfigStore(configDirectory: String?) -> SwooshConfigStore {
    SwooshConfigStore(configDirectory: resolvedSwooshConfigDirectory(configDirectory))
}

func resolvedSwooshConfigDirectory(_ path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    let expanded: String
    if path == "~" {
        expanded = FileManager.default.homeDirectoryForCurrentUser.path
    } else if path.hasPrefix("~/") {
        expanded = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2)))
            .path
    } else {
        expanded = path
    }
    let url = URL(fileURLWithPath: expanded)
    if url.path.hasPrefix("/") {
        return url.standardizedFileURL
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(expanded)
        .standardizedFileURL
}
