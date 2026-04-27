import SwiftUI

/// Typography tokens — tvOS values are larger than mobile because the user
/// sits ~3 metres from the screen.
///
/// Sizes track Apple's tvOS HIG: titles ~57pt, headlines ~38pt, body ~29pt.
enum AWATypography {
    static let display = Font.system(size: 76, weight: .bold, design: .rounded)
    static let title1 = Font.system(size: 57, weight: .semibold, design: .rounded)
    static let title2 = Font.system(size: 38, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 31, weight: .medium, design: .rounded)
    static let body = Font.system(size: 29, weight: .regular)
    static let callout = Font.system(size: 25, weight: .regular)
    static let caption = Font.system(size: 21, weight: .regular)
    static let mono = Font.system(size: 23, weight: .regular, design: .monospaced)
}

extension View {
    /// Apply a soft brand-purple glow when the view is focused — used by
    /// `PosterCard`, `ChannelTile` etc. so every focusable surface in the app
    /// breathes consistently.
    func focusGlow(_ isFocused: Bool, radius: CGFloat = 24) -> some View {
        self.shadow(
            color: isFocused ? BrandColors.primaryLight.opacity(0.55) : .clear,
            radius: isFocused ? radius : 0,
            x: 0,
            y: isFocused ? 12 : 0
        )
    }
}
