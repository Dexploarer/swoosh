// SwooshVision/Exports.swift
// Version: 0.9S
//
// Module roof. The default vision provider is Apple Vision — on-device,
// free, ubiquitous. Callers who want a different backend (e.g. a hosted
// document OCR like GLM-OCR) construct a custom provider and pass it in.

import Foundation

public enum SwooshVision {
    public static func defaultProvider() -> any VisionProviding {
        AppleVisionProvider()
    }
}
