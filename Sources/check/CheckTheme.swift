import SwiftUI

enum CheckTheme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.11, green: 0.12, blue: 0.16),
            Color(red: 0.15, green: 0.16, blue: 0.21)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let panel = Color(red: 0.17, green: 0.18, blue: 0.24)
    static let panelElevated = Color(red: 0.21, green: 0.22, blue: 0.29)
    static let border = Color.white.opacity(0.14)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.62)
    static let working = Color(red: 0.35, green: 0.88, blue: 0.63)
    static let offWork = Color(red: 0.56, green: 0.66, blue: 0.78)
    static let pending = Color(red: 1.0, green: 0.72, blue: 0.33)
    static let accent = Color(red: 0.33, green: 0.67, blue: 1.0)
}
