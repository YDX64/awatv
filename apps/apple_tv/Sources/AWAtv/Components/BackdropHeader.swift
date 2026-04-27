import SwiftUI

/// Hero header for VOD / series detail screens.
///
/// Layered:
/// 1. Async backdrop image (or branded gradient fallback)
/// 2. Dark gradient scrim that fades the bottom into the page background
/// 3. Title block with overview, rating, year and primary action slot
struct BackdropHeader<Action: View>: View {
    let title: String
    let overview: String?
    let backdropUrl: String?
    let rating: Double?
    let year: Int?
    let genres: [String]
    @ViewBuilder var action: () -> Action

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .frame(maxWidth: .infinity)
                .frame(height: 720)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.4), BrandColors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 720)

            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(AWATypography.display)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)

                HStack(spacing: 16) {
                    if let rating { RatingPill(rating: rating) }
                    if let year { metaChip(text: "\(year)") }
                    ForEach(genres.prefix(3), id: \.self) { genre in
                        metaChip(text: genre)
                    }
                }

                if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(AWATypography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(4)
                        .frame(maxWidth: 1100, alignment: .leading)
                }

                action()
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
    }

    private func metaChip(text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.white.opacity(0.18), in: Capsule())
    }

    @ViewBuilder
    private var backdrop: some View {
        if let urlString = backdropUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    BrandColors.heroGradient.opacity(0.4)
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    BrandColors.heroGradient.opacity(0.4)
                @unknown default:
                    BrandColors.heroGradient.opacity(0.4)
                }
            }
        } else {
            BrandColors.heroGradient.opacity(0.4)
        }
    }
}
