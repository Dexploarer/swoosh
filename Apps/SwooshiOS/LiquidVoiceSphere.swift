// Apps/SwooshiOS/LiquidVoiceSphere.swift — 0.9R Floating liquid voice sphere
//
// Canvas-rendered liquid orb that pulses and deforms with live audio
// level (`AudioLevelSource`). Three concentric blobs offset by sine
// waves at different phases give the metaball look without a real
// shader — fast on iPhone, no MetalKit dep.
//
// Appears as a floating overlay whenever the source reports `isActive`
// (mic listening OR TTS playback). Tap → toggles voice mode; drag →
// reposition. Haptics modulated in lockstep via VoiceHapticsCoordinator.

import SwiftUI

struct LiquidVoiceSphere: View {
    @Environment(AudioLevelSource.self) private var levels
    @State private var offset: CGSize = CGSize(width: 0, height: -180)
    @State private var dragStart: CGSize?
    let onTap: () -> Void

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            sphere(time: t)
                .frame(width: 120, height: 120)
                .offset(offset)
                .gesture(dragGesture)
                .onTapGesture { onTap() }
                .opacity(levels.isActive ? 1.0 : 0.55)
                .animation(.easeOut(duration: 0.25), value: levels.isActive)
                .onChange(of: levels.level) { _, newValue in
                    VoiceHapticsCoordinator.shared.update(level: newValue)
                }
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice sphere — tap to toggle voice mode")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sphere rendering

    private func sphere(time: TimeInterval) -> some View {
        let level = CGFloat(levels.level)
        let pulse = 1.0 + level * 0.45
        let glowAmt = 0.35 + level * 0.65

        return Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let baseRadius = min(size.width, size.height) / 2 * 0.78 * pulse
            Self.drawMetaballs(into: &ctx, center: center, baseRadius: baseRadius, level: level, time: time)
            Self.drawCore(into: &ctx, center: center, baseRadius: baseRadius, level: level)
        }
        .blur(radius: 1.5 + level * 2.0)
        .shadow(color: Color.cyan.opacity(glowAmt), radius: 24 + level * 14)
        .background(
            Circle()
                .fill(Color.cyan.opacity(0.06))
                .blur(radius: 18)
                .scaleEffect(pulse * 1.1)
        )
    }

    /// Three offset metaballs around the centre. Each blob's offset and
    /// scale follow its own sine — gives the gelatinous warble.
    private static func drawMetaballs(
        into ctx: inout GraphicsContext,
        center: CGPoint,
        baseRadius: CGFloat,
        level: CGFloat,
        time: TimeInterval
    ) {
        for blobIndex in 0..<3 {
            let phase = time * (0.9 + Double(blobIndex) * 0.27)
            let dx = CGFloat(sin(phase + Double(blobIndex) * 1.7)) * baseRadius * (0.10 + level * 0.30)
            let dy = CGFloat(cos(phase * 1.1 + Double(blobIndex) * 0.9)) * baseRadius * (0.10 + level * 0.30)
            let radius = baseRadius * (0.65 + 0.18 * CGFloat(sin(phase * 0.7)))
            let rect = CGRect(
                x: center.x + dx - radius, y: center.y + dy - radius,
                width: radius * 2, height: radius * 2
            )
            ctx.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.cyan.opacity(0.85),
                        Color.cyan.opacity(0.20),
                        Color.cyan.opacity(0.0)
                    ]),
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    startRadius: 0, endRadius: radius
                )
            )
        }
    }

    /// Bright inner core — the "highlight".
    private static func drawCore(
        into ctx: inout GraphicsContext,
        center: CGPoint,
        baseRadius: CGFloat,
        level: CGFloat
    ) {
        let coreRadius = baseRadius * (0.32 + level * 0.18)
        let coreRect = CGRect(
            x: center.x - coreRadius * 0.85, y: center.y - coreRadius,
            width: coreRadius * 2, height: coreRadius * 2
        )
        ctx.fill(
            Path(ellipseIn: coreRect),
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.85),
                    Color.cyan.opacity(0.4),
                    Color.cyan.opacity(0)
                ]),
                center: CGPoint(x: coreRect.midX, y: coreRect.midY),
                startRadius: 0, endRadius: coreRadius
            )
        )
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil { dragStart = offset }
                let s = dragStart ?? .zero
                offset = CGSize(
                    width: s.width + value.translation.width,
                    height: s.height + value.translation.height
                )
            }
            .onEnded { _ in
                dragStart = nil
            }
    }
}
