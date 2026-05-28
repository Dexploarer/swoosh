// SwooshUI/Voice/SwooshOrbView.swift — macOS-native orb animation
//
// A faithful port of metasidd/Orb (https://github.com/metasidd/Orb)
// rewritten to avoid UIKit dependencies (UIColor, UIGraphicsImageRenderer)
// that don't exist on macOS. The particle layer uses pure SwiftUI Canvas
// instead of SpriteKit + UIKit.
//
// All credit to Siddhant Mehta for the original design.

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Configuration
// ═══════════════════════════════════════════════════════════════════

public struct SwooshOrbConfiguration: Sendable {
    public let backgroundColors: [Color]
    public let glowColor: Color
    public let coreGlowIntensity: Double
    public let showParticles: Bool
    public let showShadow: Bool
    public let speed: Double

    public init(
        backgroundColors: [Color] = [.green, .blue, .pink],
        glowColor: Color = .white,
        coreGlowIntensity: Double = 1.0,
        showParticles: Bool = true,
        showShadow: Bool = true,
        speed: Double = 60
    ) {
        self.backgroundColors = backgroundColors
        self.glowColor = glowColor
        self.coreGlowIntensity = coreGlowIntensity
        self.showParticles = showParticles
        self.showShadow = showShadow
        self.speed = speed
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Orb View (public entry point)
// ═══════════════════════════════════════════════════════════════════

public struct SwooshOrbView: View {
    private let config: SwooshOrbConfiguration

    public init(configuration: SwooshOrbConfiguration = SwooshOrbConfiguration()) {
        self.config = configuration
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Base gradient background
                LinearGradient(
                    colors: config.backgroundColors,
                    startPoint: .bottom,
                    endPoint: .top
                )

                // Depth glows (rotating masked circles)
                baseDepthGlows(size: size)

                // Wavy blob layers
                wavyBlob(size: size, speed: config.speed * 1.5, direction: 1, loopDuration: 60 / config.speed * 1.75, offsetY: 0.31, scale: 1.875, opacity: 1.0)
                wavyBlob(size: size, speed: config.speed * 0.75, direction: -1, loopDuration: 60 / config.speed * 2.25, offsetY: -0.31, scale: 1.25, opacity: 0.5)
                    .rotationEffect(.degrees(90))

                // Core glow
                coreGlowEffects(size: size)

                // Pure SwiftUI particles
                if config.showParticles {
                    OrbParticlesView()
                        .frame(maxWidth: size, maxHeight: size)
                }
            }
            .overlay { realisticInnerGlows }
            .mask { Circle() }
            .aspectRatio(1, contentMode: .fit)
            .modifier(
                OrbShadowModifier(
                    colors: config.showShadow ? config.backgroundColors : [.clear],
                    radius: size * 0.08
                )
            )
        }
    }

    // MARK: - Depth glows

    private func baseDepthGlows(size: CGFloat) -> some View {
        ZStack {
            OrbRotatingGlowView(color: config.glowColor, rotationSpeed: config.speed * 0.75, direction: -1)
                .padding(size * 0.03)
                .blur(radius: size * 0.06)
                .rotationEffect(.degrees(180))
                .blendMode(.destinationOver)

            OrbRotatingGlowView(color: config.glowColor.opacity(0.5), rotationSpeed: config.speed * 0.25, direction: 1)
                .frame(maxWidth: size * 0.94)
                .rotationEffect(.degrees(180))
                .padding(8)
                .blur(radius: size * 0.032)
        }
    }

    // MARK: - Wavy blob

    private func wavyBlob(size: CGFloat, speed: Double, direction: Double, loopDuration: Double, offsetY: Double, scale: Double, opacity: Double) -> some View {
        OrbRotatingGlowView(color: .white.opacity(0.75), rotationSpeed: speed, direction: direction)
            .mask {
                OrbWavyBlobView(loopDuration: loopDuration)
                    .frame(maxWidth: size * scale)
                    .offset(y: size * offsetY)
            }
            .blur(radius: 1)
            .blendMode(.plusLighter)
            .opacity(opacity)
    }

    // MARK: - Core glow

    private func coreGlowEffects(size: CGFloat) -> some View {
        ZStack {
            OrbRotatingGlowView(color: config.glowColor, rotationSpeed: config.speed * 3, direction: 1)
                .blur(radius: size * 0.08)
                .opacity(config.coreGlowIntensity)

            OrbRotatingGlowView(color: config.glowColor, rotationSpeed: config.speed * 2.3, direction: 1)
                .blur(radius: size * 0.06)
                .opacity(config.coreGlowIntensity)
                .blendMode(.plusLighter)
        }
        .padding(size * 0.08)
    }

    // MARK: - Inner glows

    private var realisticInnerGlows: some View {
        let gradient = LinearGradient(colors: [.white, .clear], startPoint: .bottom, endPoint: .top)
        return ZStack {
            Circle().stroke(gradient, lineWidth: 8).blur(radius: 32).blendMode(.plusLighter)
            Circle().stroke(gradient, lineWidth: 4).blur(radius: 12).blendMode(.plusLighter)
            Circle().stroke(gradient, lineWidth: 1).blur(radius: 4).blendMode(.plusLighter)
        }
        .padding(1)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Rotating Glow (macOS-safe, no UIKit)
// ═══════════════════════════════════════════════════════════════════

private struct OrbRotatingGlowView: View {
    @State private var rotation: Double = 0
    let color: Color
    let rotationSpeed: Double
    let direction: Double  // 1 = CW, -1 = CCW

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            Circle()
                .fill(color)
                .mask {
                    ZStack {
                        Circle()
                            .frame(width: size, height: size)
                            .blur(radius: size * 0.16)
                        Circle()
                            .frame(width: size * 1.31, height: size * 1.31)
                            .offset(y: size * 0.31)
                            .blur(radius: size * 0.16)
                            .blendMode(.destinationOut)
                    }
                }
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 360 / max(rotationSpeed, 1)).repeatForever(autoreverses: false)) {
                        rotation = 360 * direction
                    }
                }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Wavy Blob (Canvas-based, no UIKit)
// ═══════════════════════════════════════════════════════════════════

private struct OrbWavyBlobView: View {
    @State private var points: [CGPoint] = (0..<6).map { index in
        let angle = (Double(index) / 6) * 2 * .pi
        return CGPoint(x: 0.5 + cos(angle) * 0.9, y: 0.5 + sin(angle) * 0.9)
    }

    private let loopDuration: Double

    init(loopDuration: Double = 1) {
        self.loopDuration = loopDuration
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let timeNow = timeline.date.timeIntervalSinceReferenceDate
                let angle = (timeNow.remainder(dividingBy: loopDuration) / loopDuration) * 2 * .pi
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.45

                let adjustedPoints = points.enumerated().map { index, point in
                    let phaseOffset = Double(index) * .pi / 3
                    let xOffset = sin(angle + phaseOffset) * 0.15
                    let yOffset = cos(angle + phaseOffset) * 0.15
                    return CGPoint(
                        x: (point.x - 0.5 + xOffset) * radius + center.x,
                        y: (point.y - 0.5 + yOffset) * radius + center.y
                    )
                }

                var path = Path()
                path.move(to: adjustedPoints[0])

                for i in 0..<adjustedPoints.count {
                    let next = (i + 1) % adjustedPoints.count
                    let currentAngle = atan2(adjustedPoints[i].y - center.y, adjustedPoints[i].x - center.x)
                    let nextAngle = atan2(adjustedPoints[next].y - center.y, adjustedPoints[next].x - center.x)
                    let handleLength = radius * 0.33

                    let control1 = CGPoint(
                        x: adjustedPoints[i].x + cos(currentAngle + .pi / 2) * handleLength,
                        y: adjustedPoints[i].y + sin(currentAngle + .pi / 2) * handleLength
                    )
                    let control2 = CGPoint(
                        x: adjustedPoints[next].x + cos(nextAngle - .pi / 2) * handleLength,
                        y: adjustedPoints[next].y + sin(nextAngle - .pi / 2) * handleLength
                    )

                    path.addCurve(to: adjustedPoints[next], control1: control1, control2: control2)
                }

                context.fill(path, with: .color(.white))
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Particles (pure SwiftUI Canvas — replaces SpriteKit + UIKit)
// ═══════════════════════════════════════════════════════════════════

private struct OrbParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var size: CGFloat
    var opacity: Double
    var velocity: CGPoint
    var lifetime: Double
    var age: Double = 0
}

private struct OrbParticlesView: View {
    @State private var seed: UInt64 = UInt64.random(in: 0...UInt64.max)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2
                let cy = size.height / 2
                let r = min(size.width, size.height) * 0.42

                // Deterministic particles based on seed
                for i in 0..<20 {
                    let s = Double(seed &+ UInt64(i))
                    let phase = s.truncatingRemainder(dividingBy: 7.0) + 1.0
                    let orbit = (s.truncatingRemainder(dividingBy: 5.0) / 5.0) * 0.8 + 0.1
                    let speedMul = (s.truncatingRemainder(dividingBy: 3.0) / 3.0) * 0.8 + 0.4
                    let angle = time * speedMul + phase * 2.13
                    let wobble = sin(time * 1.3 + phase) * 0.1

                    let px = cx + cos(angle) * r * (orbit + wobble)
                    let py = cy + sin(angle * 0.7 + phase) * r * (orbit + wobble * 0.5)

                    let fadePhase = (sin(time * 2 + phase * 1.7) + 1) / 2
                    let alpha = fadePhase * 0.6 + 0.05
                    let dotSize = (s.truncatingRemainder(dividingBy: 2.0) / 2.0) * 2.5 + 0.5

                    let rect = CGRect(x: px - dotSize / 2, y: py - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Circle().path(in: rect), with: .color(.white.opacity(alpha)))
                }
            }
            .blendMode(.plusLighter)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shadow modifier
// ═══════════════════════════════════════════════════════════════════

private struct OrbShadowModifier: ViewModifier {
    let colors: [Color]
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .blur(radius: radius * 0.75)
                    .opacity(0.5)
                    .offset(y: radius * 0.5)
            }
            .background {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .blur(radius: radius * 3)
                    .opacity(0.3)
                    .offset(y: radius * 0.75)
            }
    }
}
