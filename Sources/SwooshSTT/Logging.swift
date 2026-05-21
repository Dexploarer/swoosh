// SwooshSTT/Logging.swift — 0.9R os.Logger for STT engines

import Foundation
import os

internal enum STTLogger {
    static let whisper = os.Logger(subsystem: "ai.swoosh", category: "stt.whisper")
    static let system  = os.Logger(subsystem: "ai.swoosh", category: "stt.system")
}
