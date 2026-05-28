// SwooshUI/Gaming/InteractiveController.swift — SVG controller + active press overlays — 0.9U
//
// Uses high-quality SVG base images and transparent PNG button-press overlays
// from AL2009man/Gamepad-Asset-Pack. When the agent (or NitroGen) presses a
// button, the matching overlay fades in on top of the base SVG with a glow.
//
// Xbox: xbox_base.svg  + xbox_active/XBSeries_*.png
// PS5:  ds_base.svg    + ds_active/DualSense_*.png

#if os(macOS)

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Controller button identity
// ═══════════════════════════════════════════════════════════════════

public enum ControllerButton: String, CaseIterable, Sendable {
    // Face buttons
    case a, b, x, y                          // Xbox
    case cross, circle, square, triangle     // PlayStation
    // Shoulders
    case lb, rb, lt, rt
    case l1, r1, l2, r2
    // Sticks
    case leftStick, rightStick
    // D-pad
    case dpadUp, dpadDown, dpadLeft, dpadRight
    // Center
    case menu, view, share, guide
    case options, create, ps, touchpad
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - InteractiveControllerView
// ═══════════════════════════════════════════════════════════════════

public struct InteractiveControllerView: View {
    public enum Layout: String, Sendable { case xbox, playstation }

    let layout: Layout
    let accentColor: Color
    @Binding var pressedButtons: Set<ControllerButton>

    public init(layout: Layout, accentColor: Color, pressedButtons: Binding<Set<ControllerButton>>) {
        self.layout = layout
        self.accentColor = accentColor
        self._pressedButtons = pressedButtons
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Base SVG controller body ─────────────────────
                svgBaseImage
                    .frame(width: geo.size.width, height: geo.size.height)

                // ── Active press overlays ────────────────────────
                ForEach(activeOverlays, id: \.button) { overlay in
                    overlayImage(overlay, in: geo.size)
                }
            }
        }
        .aspectRatio(layout == .xbox ? 1.05 : 1.0, contentMode: .fit)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - SVG base image
    // ─────────────────────────────────────────────────────────────────

    private var svgBaseName: String {
        layout == .playstation ? "ds_base" : "xbox_base"
    }

    @ViewBuilder
    private var svgBaseImage: some View {
        if let url = Bundle.module.url(forResource: svgBaseName, withExtension: "svg", subdirectory: "GamingIcons"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let url = Bundle.main.url(forResource: svgBaseName, withExtension: "svg", subdirectory: "GamingIcons"),
                  let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 80))
                .foregroundStyle(accentColor.opacity(0.2))
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Active press overlay compositing
    // ─────────────────────────────────────────────────────────────────

    private struct ButtonOverlay: Sendable {
        let button: ControllerButton
        let filename: String      // PNG filename without extension
        let subdirectory: String  // "xbox_active" or "ds_active"
    }

    private var activeOverlays: [ButtonOverlay] {
        pressedButtons.compactMap { button in
            guard let info = overlayInfo(for: button) else { return nil }
            return ButtonOverlay(button: button, filename: info.0, subdirectory: info.1)
        }
    }

    @ViewBuilder
    private func overlayImage(_ overlay: ButtonOverlay, in size: CGSize) -> some View {
        let subdir = "GamingIcons/\(overlay.subdirectory)"
        if let url = Bundle.module.url(forResource: overlay.filename, withExtension: "png", subdirectory: subdir),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .blendMode(.plusLighter)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.08), value: pressedButtons)
        } else if let url = Bundle.main.url(forResource: overlay.filename, withExtension: "png", subdirectory: subdir),
                  let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .blendMode(.plusLighter)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.08), value: pressedButtons)
        }
    }

    /// Maps each button to its overlay PNG filename + subdirectory
    private func overlayInfo(for button: ControllerButton) -> (String, String)? {
        if layout == .xbox {
            return xboxOverlay(for: button)
        } else {
            return psOverlay(for: button)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Xbox overlay mapping
    // ─────────────────────────────────────────────────────────────────

    private func xboxOverlay(for button: ControllerButton) -> (String, String)? {
        let dir = "xbox_active"
        switch button {
        case .a:          return ("XBSeries_A_Button", dir)
        case .b:          return ("XBSeries_B_Button", dir)
        case .x:          return ("XBSeries_X_Button", dir)
        case .y:          return ("XBSeries_Y_Button", dir)
        case .lb:         return ("XBSeries_LeftBumper_Active", dir)
        case .rb:         return ("XBSeries_RightBumper_Active", dir)
        case .lt:         return ("XBSeries_LeftTrigger_Active", dir)
        case .rt:         return ("XBSeries_RightTrigger_Active", dir)
        case .leftStick:  return ("XBSeries_LeftStick_Click", dir)
        case .rightStick: return ("XBSeries_RightStick_Click", dir)
        case .dpadUp:     return ("XBSeries_D-PAD_Up", dir)
        case .dpadDown:   return ("XBSeries_D-PAD_Down", dir)
        case .dpadLeft:   return ("XBSeries_D-PAD_Left", dir)
        case .dpadRight:  return ("XBSeries_D-PAD_Right", dir)
        case .guide:      return ("XBSeries_HomeButton", dir)
        case .menu:       return ("XBSeries_MenuButton", dir)
        case .view:       return ("XBSeries_ViewButton", dir)
        case .share:      return ("XBSeries_ShareButton", dir)
        default:          return nil  // PS-only buttons
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - PlayStation overlay mapping
    // ─────────────────────────────────────────────────────────────────

    private func psOverlay(for button: ControllerButton) -> (String, String)? {
        let dir = "ds_active"
        switch button {
        case .cross:      return ("DualSense_Cross", dir)
        case .circle:     return ("DualSense_Circle", dir)
        case .square:     return ("DualSense_Square", dir)
        case .triangle:   return ("DualSense_Triangle", dir)
        case .l1:         return ("DualSense_L1-Active", dir)
        case .r1:         return ("DualSense_R1-Active", dir)
        case .l2:         return ("DualSense_L2-Active", dir)
        case .r2:         return ("DualSense_R2-Active", dir)
        case .leftStick:  return ("DualSense_AnalogStick_Click", dir)
        case .rightStick: return ("DualSense_AnalogStick_Click", dir)
        case .dpadUp:     return ("DualSense_D-PAD_Up", dir)
        case .dpadDown:   return ("DualSense_D-PAD_Down", dir)
        case .dpadLeft:   return ("DualSense_D-PAD_Left", dir)
        case .dpadRight:  return ("DualSense_D-PAD_Right", dir)
        case .ps:         return ("DualSense_Home_Button", dir)
        case .options:    return ("DualSense_Option_Button", dir)
        case .create:     return ("DualSense_Create_Button", dir)
        case .touchpad:   return ("DualSense_Touchpad-Click", dir)
        default:          return nil  // Xbox-only buttons
        }
    }
}

#endif
