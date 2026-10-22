import AppKit
import SwiftUI

/// Design tokens. Every colour adapts to light and dark mode on its own; views never hard-code values.
enum AppTheme {
    enum Colors {
        /// Window background, the darkest (or lightest) layer.
        static let background = Color(light: .hex(0xF4F4F1), dark: .hex(0x0D0E10))
        /// Top of the background gradient and raised elements such as the selected segment.
        static let backgroundRaised = Color(light: .hex(0xFFFFFF), dark: .hex(0x1A1C20))
        /// Laid over `.ultraThinMaterial` so surfaces read the same on any wallpaper.
        static let surfaceTint = Color(light: .white.withAlphaComponent(0.55), dark: .white.withAlphaComponent(0.03))
        /// Recessed areas: segmented-control tracks, icon tiles, progress tracks.
        static let well = Color(light: .black.withAlphaComponent(0.05), dark: .black.withAlphaComponent(0.30))
        static let hover = Color(light: .black.withAlphaComponent(0.05), dark: .white.withAlphaComponent(0.07))
        static let border = Color(light: .black.withAlphaComponent(0.08), dark: .white.withAlphaComponent(0.08))
        static let borderStrong = Color(light: .black.withAlphaComponent(0.15), dark: .white.withAlphaComponent(0.16))

        static let textPrimary = Color(light: .hex(0x121316), dark: .hex(0xF3F3F0))
        /// At least 4.5:1 against `background` in both modes.
        static let textSecondary = Color(light: .hex(0x5C5F66), dark: .hex(0x9EA1A8))

        /// The one accent: chartreuse in dark mode, deep olive in light mode (both ≥ 4.5:1 with `onAccent`).
        static let accent = Color(light: .hex(0x3F6E00), dark: .hex(0xC6F35E))
        static let onAccent = Color(light: .white, dark: .hex(0x0D0E10))

        /// Switch knobs: light in both modes so they read on the accent and on the empty track.
        static let knob = Color(light: .white, dark: .hex(0xF3F3F0))

        static let warning = Color(light: .hex(0x8A5D00), dark: .hex(0xE8B94F))
        static let danger = Color(light: .hex(0xB3261E), dark: .hex(0xFF6B60))
        static let onDanger = Color(light: .white, dark: .hex(0x0D0E10))
    }

    /// The 4-pt grid.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Metrics {
        /// Minimum hit area of anything clickable.
        static let hitTarget: CGFloat = 44
        static let sidebarWidth: CGFloat = 248
    }

    enum Motion {
        /// Selection, insertion and layout changes.
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.75)
        /// Press feedback: quicker so it tracks the pointer.
        static let press = Animation.spring(response: 0.22, dampingFraction: 0.8)
    }
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension RoundedRectangle {
    /// Continuous ("squircle") corners, as used throughout macOS and iOS.
    static func themed(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
