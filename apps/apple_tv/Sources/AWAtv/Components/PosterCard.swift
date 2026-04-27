import SwiftUI

/// A focusable poster tile used by VOD and Series grids.
///
/// Produces the signature tvOS feel:
/// - Native focus engine ring courtesy of `.focusable()`
/// - 1.05× scale on focus driven by `@FocusState`
/// - Soft brand-purple glow underneath via `focusGlow`
/// - Asynchronous image load with a placeholder shimmer
struct PosterCard: View {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let posterUrl: String?
        let rating: Double?
        let year: Int?
    }

    let item: Item

    @Environment(\.isFocused) private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                poster
                if let rating = item.rating {
                    RatingPill(rating: rating)
                        .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(AWATypography.headline)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(2)

                if let year = item.year {
                    Text(verbatim: "\(year)")
                        .font(AWATypography.caption)
                        .foregroundStyle(BrandColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280)
        .padding(8)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
        .focusGlow(isFocused)
    }

    @ViewBuilder
    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandColors.surface)

            if let urlString = item.posterUrl,
               let url = URL(string: urlString)
            {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(BrandColors.primaryLight)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholderArt
                    @unknown default:
                        placeholderArt
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                placeholderArt
            }
        }
        .frame(width: 264, height: 396)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isFocused ? BrandColors.primaryLight : .white.opacity(0.06), lineWidth: 2)
        )
    }

    private var placeholderArt: some View {
        ZStack {
            BrandColors.heroGradient
                .opacity(0.25)
            Image(systemName: "film")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(BrandColors.textMuted)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    PosterCard(
        item: .init(
            id: "1",
            title: "The Tea Party of the Century",
            posterUrl: nil,
            rating: 7.8,
            year: 2024
        )
    )
    .padding(60)
    .background(BrandColors.background)
}
