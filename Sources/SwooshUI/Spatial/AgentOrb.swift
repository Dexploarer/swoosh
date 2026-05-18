// SwooshUI/Spatial/AgentOrb.swift — Live 3D agent activity indicator (0.4A)
//
// A pulsing RealityKit sphere whose displacement, color, and rotation
// respond to the agent's state. Pure-code mesh, no USDZ shipped — that
// means it works on any target without an asset bundle and can be tinted
// from the active SwooshTheme.
//
// State model:
//   - .idle    → slow breathing, soft tint
//   - .thinking → faster pulse, accent color
//   - .acting   → high-frequency rotation, warning tint when waiting on
//                 approval, success tint when complete.

import SwiftUI
#if canImport(RealityKit)
import RealityKit
#endif

// MARK: - Public state

public enum SwooshAgentOrbState: Sendable, Equatable {
    case idle
    case thinking
    case acting
    case awaitingApproval
    case completed
    case error
}

public struct SwooshAgentOrb: View {
    public let state: SwooshAgentOrbState
    public let size: CGFloat

    @Environment(\.swooshTheme) var theme

    public init(state: SwooshAgentOrbState = .idle, size: CGFloat = 64) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        #if canImport(RealityKit) && !targetEnvironment(simulator)
        if #available(macOS 14.0, iOS 17.0, *) {
            RealityViewOrb(state: state, tint: orbTint, size: size)
                .frame(width: size, height: size)
        } else {
            FallbackOrb(state: state, tint: orbTint, size: size)
        }
        #else
        FallbackOrb(state: state, tint: orbTint, size: size)
        #endif
    }

    private var orbTint: Color {
        switch state {
        case .idle:             return theme.textSecondary
        case .thinking:         return theme.accent
        case .acting:           return theme.info
        case .awaitingApproval: return theme.warning
        case .completed:        return theme.success
        case .error:            return theme.error
        }
    }
}

// MARK: - RealityKit implementation

#if canImport(RealityKit)
@available(macOS 14.0, iOS 17.0, *)
private struct RealityViewOrb: View {
    let state: SwooshAgentOrbState
    let tint: Color
    let size: CGFloat

    var body: some View {
        RealityView { content in
            let mesh = MeshResource.generateSphere(radius: 0.4)
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: tintPlatformColor)
            material.metallic = .init(floatLiteral: 0.4)
            material.roughness = .init(floatLiteral: 0.25)
            material.emissiveColor = .init(color: tintPlatformColor)
            material.emissiveIntensity = 0.6
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "swoosh-orb"
            content.add(entity)
        } update: { content in
            // Drive rotation by date so the animation stays consistent across
            // re-renders when state changes.
            let t = Date().timeIntervalSinceReferenceDate
            let speed = rotationSpeed
            let angle = Float(t * speed)
            for entity in content.entities {
                entity.transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0.2])
                let scale = pulseScale(at: t)
                entity.transform.scale = [scale, scale, scale]
            }
        }
        .background(.clear)
    }

    private var rotationSpeed: Double {
        switch state {
        case .idle:             return 0.15
        case .thinking:         return 0.6
        case .acting:           return 1.4
        case .awaitingApproval: return 0.4
        case .completed:        return 0.25
        case .error:            return 0.0
        }
    }

    private func pulseScale(at t: TimeInterval) -> Float {
        let frequency: Double
        let amplitude: Double
        switch state {
        case .idle:             frequency = 0.4;  amplitude = 0.03
        case .thinking:         frequency = 1.6;  amplitude = 0.06
        case .acting:           frequency = 3.0;  amplitude = 0.08
        case .awaitingApproval: frequency = 1.0;  amplitude = 0.10
        case .completed:        frequency = 0.6;  amplitude = 0.04
        case .error:            frequency = 0.0;  amplitude = 0.0
        }
        return Float(1.0 + sin(t * .pi * 2 * frequency) * amplitude)
    }

    #if os(macOS)
    private var tintPlatformColor: NSColor {
        NSColor(tint)
    }
    #else
    private var tintPlatformColor: UIColor {
        UIColor(tint)
    }
    #endif
}

#if os(macOS)
import AppKit
#endif
#if os(iOS) || os(visionOS)
import UIKit
#endif
#endif

// MARK: - 2D fallback

private struct FallbackOrb: View {
    let state: SwooshAgentOrbState
    let tint: Color
    let size: CGFloat

    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint, tint.opacity(0.25), tint.opacity(0)],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.55
                    )
                )

            Circle()
                .strokeBorder(tint.opacity(0.45), lineWidth: 1.2)
                .scaleEffect(1 + 0.05 * sin(phase))

            Circle()
                .fill(tint.opacity(0.9))
                .frame(width: size * 0.3, height: size * 0.3)
                .blur(radius: 4)
                .opacity(0.6 + 0.4 * abs(sin(phase * 0.7)))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: durationFor(state))
                .repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }

    private func durationFor(_ s: SwooshAgentOrbState) -> Double {
        switch s {
        case .idle:             return 2.4
        case .thinking:         return 0.9
        case .acting:           return 0.5
        case .awaitingApproval: return 1.2
        case .completed:        return 1.6
        case .error:            return 3.0
        }
    }
}
