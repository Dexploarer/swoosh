// SwooshCore/PersonalizationPromptContext.swift — Detour setup calibration prompt context

import Foundation

public struct PersonalizationPromptContext: Sendable, Equatable {
    public let userName: String
    public let agentName: String
    public let eventRoutes: [String]
    public let shouldRespondTemplate: String
    public let messageHandlerTemplate: String
    public let reflectionTemplate: String
    public let machineEventTemplate: String

    public init(
        userName: String,
        agentName: String,
        eventRoutes: [String],
        shouldRespondTemplate: String,
        messageHandlerTemplate: String,
        reflectionTemplate: String,
        machineEventTemplate: String
    ) {
        self.userName = userName
        self.agentName = agentName
        self.eventRoutes = eventRoutes
        self.shouldRespondTemplate = shouldRespondTemplate
        self.messageHandlerTemplate = messageHandlerTemplate
        self.reflectionTemplate = reflectionTemplate
        self.machineEventTemplate = machineEventTemplate
    }
}

public protocol PersonalizationContextLoading: Sendable {
    func loadPersonalizationContext() async throws -> PersonalizationPromptContext?
}

public struct FilePersonalizationContextLoader: PersonalizationContextLoading {
    private let swooshDirectory: URL

    public init(
        swooshDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
    ) {
        self.swooshDirectory = swooshDirectory
    }

    public func loadPersonalizationContext() async throws -> PersonalizationPromptContext? {
        let calibrationURL = swooshDirectory.appendingPathComponent("detour-calibration.json", isDirectory: false)
        if FileManager.default.fileExists(atPath: calibrationURL.path) {
            let data = try Data(contentsOf: calibrationURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let calibration = try decoder.decode(DetourCalibrationFile.self, from: data)
            return PersonalizationPromptContext(
                userName: calibration.userName,
                agentName: calibration.agentName,
                eventRoutes: calibration.eventRoutes.map {
                    "\($0.event): \($0.policy) [\($0.templateTag) -> \($0.contextVariable)]"
                },
                shouldRespondTemplate: calibration.templates.shouldRespondTemplate,
                messageHandlerTemplate: calibration.templates.messageHandlerTemplate,
                reflectionTemplate: calibration.templates.reflectionTemplate,
                machineEventTemplate: calibration.templates.machineEventTemplate
            )
        }

        let templatesURL = swooshDirectory
            .appendingPathComponent("templates", isDirectory: true)
            .appendingPathComponent("detour-personalization.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: templatesURL.path) else { return nil }
        let templates = try JSONDecoder().decode(
            DetourTemplateFile.self,
            from: Data(contentsOf: templatesURL)
        )
        return PersonalizationPromptContext(
            userName: "",
            agentName: "Detour",
            eventRoutes: [],
            shouldRespondTemplate: templates.shouldRespondTemplate,
            messageHandlerTemplate: templates.messageHandlerTemplate,
            reflectionTemplate: templates.reflectionTemplate,
            machineEventTemplate: templates.machineEventTemplate
        )
    }
}

private struct DetourCalibrationFile: Decodable {
    var userName: String
    var agentName: String
    var eventRoutes: [DetourEventRouteFile]
    var templates: DetourTemplateFile
}

private struct DetourEventRouteFile: Decodable {
    var event: String
    var contextVariable: String
    var templateTag: String
    var policy: String
}

private struct DetourTemplateFile: Decodable {
    var shouldRespondTemplate: String
    var messageHandlerTemplate: String
    var reflectionTemplate: String
    var machineEventTemplate: String
}
