// SwooshMusic/Logging.swift — 0.9R os.Logger for music providers

import Foundation
import os

internal enum MusicLogger {
    static let suno    = os.Logger(subsystem: "ai.swoosh", category: "music.suno")
    static let eleven  = os.Logger(subsystem: "ai.swoosh", category: "music.elevenlabs")
    static let stable  = os.Logger(subsystem: "ai.swoosh", category: "music.stable")
}
