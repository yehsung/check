import SwiftUI

enum CheckTheme {
    // Surfaces
    static let background = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.11, blue: 0.15),
            Color(red: 0.14, green: 0.15, blue: 0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let panel = Color(red: 0.17, green: 0.18, blue: 0.24)
    static let panelElevated = Color(red: 0.21, green: 0.22, blue: 0.29)
    static let border = Color.white.opacity(0.14)
    static let fieldFill = Color.black.opacity(0.20)
    static let trackFill = Color.black.opacity(0.28)

    // Text — secondaryText kept near 4.5:1 on panel
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.68)

    // Status accents (names preserved)
    static let working = Color(red: 0.35, green: 0.88, blue: 0.63)
    static let offWork = Color(red: 0.58, green: 0.68, blue: 0.80)
    static let pending = Color(red: 1.0, green: 0.72, blue: 0.33)
    static let accent = Color(red: 0.33, green: 0.67, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.45, blue: 0.46)

    // Gradients for pills / gauges
    static let startGradient = LinearGradient(
        colors: [Color(red: 0.32, green: 0.85, blue: 0.58), Color(red: 0.18, green: 0.68, blue: 0.62)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let stopGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.63, blue: 0.30), Color(red: 0.96, green: 0.36, blue: 0.40)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let gaugeGradient = LinearGradient(
        colors: [Color(red: 0.35, green: 0.88, blue: 0.63), Color(red: 0.33, green: 0.67, blue: 1.0)],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Initial-avatar palette (name-hash indexed)
    static let avatarPalette: [Color] = [
        Color(red: 0.40, green: 0.55, blue: 0.95),
        Color(red: 0.24, green: 0.74, blue: 0.71),
        Color(red: 0.95, green: 0.64, blue: 0.30),
        Color(red: 0.93, green: 0.45, blue: 0.56),
        Color(red: 0.65, green: 0.50, blue: 0.92),
        Color(red: 0.38, green: 0.79, blue: 0.55)
    ]

    static func avatarColor(for name: String) -> Color {
        guard !avatarPalette.isEmpty else { return accent }
        let seed = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return avatarPalette[abs(seed) % avatarPalette.count]
    }
}
