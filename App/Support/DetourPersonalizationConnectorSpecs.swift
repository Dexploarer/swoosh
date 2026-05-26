// DetourPersonalizationConnectorSpecs.swift — connector runtime spec helpers (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func codexConnectorPluginSpec(_ candidateID: String) -> ConnectorPluginSpec {
        let slug = candidateID.replacingOccurrences(of: "connector.", with: "")
        let displayName: String
        let requiredCredentialKeys: [String]
        let toolNameFragments: [String]
        switch candidateID {
        case "connector.figma":
            displayName = "Figma"
            requiredCredentialKeys = []
            toolNameFragments = ["figma"]
        case "connector.vercel":
            displayName = "Vercel"
            requiredCredentialKeys = ["VERCEL_TOKEN"]
            toolNameFragments = ["vercel"]
        case "connector.canva":
            displayName = "Canva"
            requiredCredentialKeys = []
            toolNameFragments = ["canva"]
        case "connector.heygen":
            displayName = "HeyGen"
            requiredCredentialKeys = []
            toolNameFragments = ["heygen"]
        case "connector.mem":
            displayName = "Mem"
            requiredCredentialKeys = []
            toolNameFragments = ["mem"]
        case "connector.jam":
            displayName = "Jam"
            requiredCredentialKeys = []
            toolNameFragments = ["jam"]
        case "connector.binance":
            displayName = "Binance"
            requiredCredentialKeys = []
            toolNameFragments = ["binance"]
        case "connector.mangaboom":
            displayName = "MangaBoom"
            requiredCredentialKeys = []
            toolNameFragments = ["mangaboom", "manga"]
        default:
            displayName = connectorDisplayName(slug)
            requiredCredentialKeys = []
            toolNameFragments = [slug]
        }
        return ConnectorPluginSpec(
            candidateID: candidateID,
            pluginID: slug,
            displayName: displayName,
            requiredCredentialKeys: requiredCredentialKeys,
            toolNameFragments: toolNameFragments
        )
    }

    func connectorDisplayName(_ slug: String) -> String {
        slug.split(separator: "-")
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}
