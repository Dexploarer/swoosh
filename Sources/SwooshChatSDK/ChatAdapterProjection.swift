// SwooshChatSDK/ChatAdapterProjection.swift — Wire DTO projection for adapter status
import Foundation
import SwooshClient

public enum ChatAdapterProjection {
    public static func response(
        platformStatuses: [ChatAdapterStatus],
        stateStatuses: [ChatStateAdapterStatus]
    ) -> ChatAdaptersResponse {
        ChatAdaptersResponse(
            adapters: platformStatuses.map {
                ChatAdapterSummary(
                    id: $0.definition.id,
                    displayName: $0.definition.displayName,
                    packageName: $0.definition.packageName,
                    distribution: $0.definition.distribution.rawValue,
                    enabled: $0.enabled,
                    configured: $0.configured,
                    missingCredentials: $0.missingCredentials,
                    configurationNotes: $0.configurationNotes,
                    supportsStreaming: $0.definition.features.supportsStreaming,
                    supportsDMs: $0.definition.features.supportsDMs,
                    supportsCards: $0.definition.features.supportsCards,
                    supportsModals: $0.definition.features.supportsModals
                )
            },
            stateAdapters: stateStatuses.map {
                ChatStateAdapterSummary(
                    id: $0.definition.id,
                    displayName: $0.definition.displayName,
                    packageName: $0.definition.packageName,
                    distribution: $0.definition.distribution.rawValue,
                    productionReady: $0.definition.productionReady,
                    enabled: $0.enabled,
                    configured: $0.configured,
                    missingCredentials: $0.missingCredentials,
                    configurationNotes: $0.configurationNotes
                )
            }
        )
    }
}
