import SwiftUI

/// Tiny chip showing a 0-10 rating from TMDB-equivalent metadata.
///
/// Colour is interpolated: <5 muted, 5-7 brand purple, >7 cyan accent.
struct RatingPill: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 16, weight: .bold))
            Text(String(format: "%.1f", rating))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(pillColor.opacity(0.85), in: Capsule())
    }

    private var pillColor: Color {
        switch rating {
        case ..<5: return .gray
        case 5..<7: return BrandColors.primary
        default: return BrandColors.accent.opacity(0.9)
        }
    }
}
