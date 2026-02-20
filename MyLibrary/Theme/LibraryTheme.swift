import SwiftUI

enum LibraryTheme {
    static let accent = Color(red: 0.70, green: 0.20, blue: 0.22)
    static let paper = Color(red: 0.97, green: 0.93, blue: 0.86)
    static let shelfBrown = Color(red: 0.55, green: 0.35, blue: 0.21)
    static let textPrimary = Color(red: 0.19, green: 0.14, blue: 0.10)
    static let textSecondary = Color(red: 0.34, green: 0.27, blue: 0.20)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.99, green: 0.78, blue: 0.45),
            Color(red: 0.97, green: 0.91, blue: 0.65),
            Color(red: 0.86, green: 0.93, blue: 0.83)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
