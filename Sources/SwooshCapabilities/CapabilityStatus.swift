// SwooshCapabilities/CapabilityStatus.swift
// Version: 0.9R
//
// Platform-availability checks used by the capability picker to gate
// rows that need a newer OS version. View-model types for a status
// snapshot live with the picker UI — this module only owns
// availability detection.

import Foundation

public enum CapabilityAvailability {
    public static var appleTranslationAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) { return true }
        return false
    }
    public static var imagePlaygroundAvailable: Bool {
        if #available(macOS 15.2, iOS 18.2, *) { return true }
        return false
    }
    public static var visionDepthAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) { return true }
        return false
    }
}
