// DetourCodexConnectorCatalog.swift — Codex connector catalog projection (0.5A)

import Foundation

struct DetourCodexConnectorCatalogItem: Equatable, Sendable {
    var connectorID: String
    var displayName: String
    var detail: String
    var namespace: String
    var toolNames: [String]
    var toolCount: Int
    var readOnlyToolCount: Int
    var actionToolCount: Int
    var destructiveToolCount: Int
    var openWorldToolCount: Int
    var containsMCPSource: Bool

    var slug: String {
        DetourCodexConnectorCatalog.slug(displayName)
    }
}

struct DetourCodexConnectorCatalogResult: Equatable, Sendable {
    var items: [DetourCodexConnectorCatalogItem]
    var skippedFiles: Int
}

enum DetourCodexConnectorCatalog {
    static func load(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DetourCodexConnectorCatalogResult {
        let directory = homeDirectory
            .appendingPathComponent(".codex")
            .appendingPathComponent("cache")
            .appendingPathComponent("codex_apps_tools")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return DetourCodexConnectorCatalogResult(items: [], skippedFiles: 0)
        }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return DetourCodexConnectorCatalogResult(items: [], skippedFiles: 1)
        }
        var buckets: [String: Bucket] = [:]
        var skippedFiles = 0
        for url in urls where url.pathExtension == "json" {
            do {
                try ingest(url: url, into: &buckets)
            } catch {
                skippedFiles += 1
            }
        }
        let items = buckets.values
            .map(\.item)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        return DetourCodexConnectorCatalogResult(items: items, skippedFiles: skippedFiles)
    }

    static func slug(_ value: String) -> String {
        let mapped = value.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let compacted = mapped.split(separator: "-").joined(separator: "-")
        return String(compacted.prefix(72)).nilIfEmpty ?? "connector"
    }

    private static func ingest(url: URL, into buckets: inout [String: Bucket]) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = root["tools"] as? [[String: Any]] else {
            throw DetourCodexConnectorCatalogError.invalidDocument
        }
        for entry in tools {
            guard let connectorID = entry["connector_id"] as? String,
                  let connectorName = entry["connector_name"] as? String else {
                continue
            }
            let namespace = entry["tool_namespace"] as? String ?? ""
            let detail = connectorDescription(entry)
            let tool = entry["tool"] as? [String: Any]
            let toolName = tool?["name"] as? String
            let annotations = tool?["annotations"] as? [String: Any]
            let meta = tool?["_meta"] as? [String: Any]
            let codexMeta = meta?["_codex_apps"] as? [String: Any]
            let key = connectorID.nilIfEmpty ?? connectorName
            var bucket = buckets[key] ?? Bucket(
                connectorID: connectorID,
                displayName: connectorName,
                detail: detail,
                namespace: namespace
            )
            bucket.add(
                toolName: toolName,
                readOnly: annotations?["readOnlyHint"] as? Bool,
                destructive: annotations?["destructiveHint"] as? Bool,
                openWorld: annotations?["openWorldHint"] as? Bool,
                containsMCPSource: codexMeta?["contains_mcp_source"] as? Bool
            )
            buckets[key] = bucket
        }
    }

    private static func connectorDescription(_ entry: [String: Any]) -> String {
        if let value = entry["namespace_description"] as? String, !value.isEmpty {
            return value
        }
        guard let tool = entry["tool"] as? [String: Any],
              let meta = tool["_meta"] as? [String: Any],
              let value = meta["connector_description"] as? String else {
            return ""
        }
        return value
    }
}

private enum DetourCodexConnectorCatalogError: Error {
    case invalidDocument
}

private struct Bucket {
    var connectorID: String
    var displayName: String
    var detail: String
    var namespace: String
    var toolNames: Set<String> = []
    var readOnlyToolCount = 0
    var actionToolCount = 0
    var destructiveToolCount = 0
    var openWorldToolCount = 0
    var containsMCPSource = false

    var item: DetourCodexConnectorCatalogItem {
        let sortedTools = toolNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return DetourCodexConnectorCatalogItem(
            connectorID: connectorID,
            displayName: displayName,
            detail: detail,
            namespace: namespace,
            toolNames: sortedTools,
            toolCount: sortedTools.count,
            readOnlyToolCount: readOnlyToolCount,
            actionToolCount: actionToolCount,
            destructiveToolCount: destructiveToolCount,
            openWorldToolCount: openWorldToolCount,
            containsMCPSource: containsMCPSource
        )
    }

    mutating func add(
        toolName: String?,
        readOnly: Bool?,
        destructive: Bool?,
        openWorld: Bool?,
        containsMCPSource: Bool?
    ) {
        guard let toolName, !toolName.isEmpty, toolNames.insert(toolName).inserted else { return }
        if readOnly == true {
            readOnlyToolCount += 1
        } else {
            actionToolCount += 1
        }
        if destructive == true {
            destructiveToolCount += 1
        }
        if openWorld == true {
            openWorldToolCount += 1
        }
        if containsMCPSource == true {
            self.containsMCPSource = true
        }
    }
}
