// SwooshUI/QuickLook/SwooshQuickLook.swift — System Quick Look preview (0.4A)
//
// Lets the user hit space (or tap a "preview" button) on a tool result and
// see it in the native Quick Look UI — same affordance Finder uses for
// files. Works for JSON, images, audio, and text. The renderer writes the
// payload to a temp file and hands the URL to `quickLookPreview`.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Result kind

public enum SwooshQuickLookKind: Sendable {
    case json
    case markdown
    case text
    case image
    case audio
    case other(extension: String)

    var fileExtension: String {
        switch self {
        case .json:                return "json"
        case .markdown:            return "md"
        case .text:                return "txt"
        case .image:               return "png"
        case .audio:               return "wav"
        case let .other(ext):      return ext
        }
    }
}

// MARK: - Open helper

public enum SwooshQuickLookOpener {
    /// Open the given URL in the system Quick Look UI. Uses NSWorkspace on
    /// macOS; on iOS the host should bridge to UIDocumentInteractionController.
    @MainActor
    public static func open(_ url: URL) {
        #if os(macOS)
        // Late-binding lookup keeps this file free of AppKit imports.
        let selector = NSSelectorFromString("sharedWorkspace")
        guard let wsClass = NSClassFromString("NSWorkspace") as? NSObject.Type,
              let workspace = wsClass.perform(selector)?.takeUnretainedValue()
        else { return }
        let act = NSSelectorFromString("openURL:")
        _ = (workspace as AnyObject).perform(act, with: url)
        #endif
    }
}

// MARK: - Stash helper

public enum SwooshQuickLookStash {
    /// Write `payload` to a temp file of the right extension and return the
    /// URL. Caller stores it in a `@State var url: URL?` and binds via
    /// `swooshQuickLook`. The temp dir auto-cleans on app exit.
    public static func stash(_ payload: Data, kind: SwooshQuickLookKind,
                             baseName: String = "swoosh-preview") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai.swoosh.quicklook", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir
            .appendingPathComponent("\(baseName)-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension(kind.fileExtension)
        try payload.write(to: url, options: .atomic)
        return url
    }

    /// String-overload — most tool outputs are textual JSON.
    public static func stash(_ string: String, kind: SwooshQuickLookKind,
                             baseName: String = "swoosh-preview") throws -> URL {
        try stash(Data(string.utf8), kind: kind, baseName: baseName)
    }
}
