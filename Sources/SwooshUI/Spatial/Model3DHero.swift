// SwooshUI/Spatial/Model3DHero.swift — Optional USDZ hero (0.4A)
//
// Drop a `swoosh.usdz` into the app bundle (or pass any URL) and this view
// renders it with `Model3D`. Falls back to a glowing sphere when the asset
// isn't available — the dashboard never gets a hole if the artist hasn't
// shipped the model yet.
//
// `Model3D` ships in SwiftUI when `RealityKit` is importable AND the platform
// has a SwiftUI integration (iOS 17+, visionOS, macOS 14+ with a Mac chip).
// We guard via `canImport(RealityKit)` plus an availability gate.

import SwiftUI
#if canImport(RealityKit)
import RealityKit
#endif

public struct SwooshModel3DHero: View {
    public let url: URL?
    public let height: CGFloat

    public init(url: URL? = nil, height: CGFloat = 220) {
        self.url = url
        self.height = height
    }

    public var body: some View {
        Group {
            #if canImport(RealityKit) && (os(iOS) || os(visionOS))
            if #available(iOS 17.0, visionOS 1.0, *), let url {
                Model3D(url: url) { phase in
                    switch phase {
                    case .empty:
                        loadingPlaceholder
                    case let .success(model):
                        model
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        SwooshAgentOrb(state: .idle, size: height * 0.55)
                    @unknown default:
                        SwooshAgentOrb(state: .idle, size: height * 0.55)
                    }
                }
            } else {
                SwooshAgentOrb(state: .idle, size: height * 0.55)
            }
            #else
            SwooshAgentOrb(state: .idle, size: height * 0.55)
            #endif
        }
        .frame(height: height)
    }

    private var loadingPlaceholder: some View {
        SwooshAgentOrb(state: .thinking, size: height * 0.55)
    }
}
