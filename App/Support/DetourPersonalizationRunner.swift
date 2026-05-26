// DetourPersonalizationRunner.swift — consented local personalization services (0.5A)

import AppKit
#if canImport(Contacts)
import Contacts
#endif
import Foundation
import OSLog
#if canImport(Security)
import Security
#endif

@MainActor
struct DetourPersonalizationRunner {
    let logger = Logger(subsystem: "ai.swoosh.detour.mac", category: "Personalization")
    let fileManager = FileManager.default
}
