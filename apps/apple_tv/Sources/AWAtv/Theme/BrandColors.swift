import SwiftUI

/// Brand palette mirrored from `awatv_ui`'s BrandColors.
///
/// Keep these literal hex values in sync with the Flutter side so cross-
/// platform screenshots feel like the same product. Hex → RGB conversion is
/// done at compile time by SwiftUI's `Color(red:green:blue:)` initializer.
enum BrandColors {
    /// Deep indigo — primary brand colour. `#FF6C5CE7`.
    static let primary = Color(red: 108.0 / 255.0, green: 92.0 / 255.0, blue: 231.0 / 255.0)

    /// Electric purple — accents, focus glow base. `#FF8E7CFF`.
    static let primaryLight = Color(red: 142.0 / 255.0, green: 124.0 / 255.0, blue: 255.0 / 255.0)

    /// Cyan — success, "now playing", live indicator. `#FF00D4FF`.
    static let accent = Color(red: 0.0 / 255.0, green: 212.0 / 255.0, blue: 255.0 / 255.0)

    /// Near-black with a hint of indigo — page background. `#FF0A0D14`.
    static let background = Color(red: 10.0 / 255.0, green: 13.0 / 255.0, blue: 20.0 / 255.0)

    /// Slightly lifted surface for cards. `#FF161A26`.
    static let surface = Color(red: 22.0 / 255.0, green: 26.0 / 255.0, blue: 38.0 / 255.0)

    /// Card surface when focused — adds a subtle highlight. `#FF222840`.
    static let surfaceFocused = Color(red: 34.0 / 255.0, green: 40.0 / 255.0, blue: 64.0 / 255.0)

    /// Magenta — premium tier, alerts. `#FFFF3D71`.
    static let pink = Color(red: 255.0 / 255.0, green: 61.0 / 255.0, blue: 113.0 / 255.0)

    /// Body text colour at full opacity.
    static let textPrimary = Color.white

    /// Muted secondary text. `0xCCFFFFFF`.
    static let textSecondary = Color.white.opacity(0.8)

    /// Tertiary text for captions. `0x80FFFFFF`.
    static let textMuted = Color.white.opacity(0.5)

    /// Linear gradient for hero backdrops and CTAs.
    static let heroGradient = LinearGradient(
        colors: [primary, primaryLight, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
