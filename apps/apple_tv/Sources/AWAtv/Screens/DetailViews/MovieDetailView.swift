import SwiftUI

/// Detail screen for a single VOD item. Hero backdrop on top, primary
/// "Play" CTA, and secondary metadata below.
struct MovieDetailView: View {
    @Environment(PlayerStore.self) private var playerStore
    let vod: VodItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackdropHeader(
                    title: vod.title,
                    overview: vod.plot,
                    backdropUrl: vod.backdropUrl ?? vod.posterUrl,
                    rating: vod.rating,
                    year: vod.year,
                    genres: vod.genres
                ) {
                    HStack(spacing: 18) {
                        Button {
                            playerStore.play(.from(vod))
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(AWATypography.headline)
                                .padding(.horizontal, 36)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandColors.accent)

                        Button {
                            // Placeholder for "Add to favourites" — Phase 5.
                        } label: {
                            Label("My List", systemImage: "plus")
                                .font(AWATypography.headline)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrandColors.primaryLight)
                    }
                }

                detailsBlock
                    .padding(.horizontal, 80)
                    .padding(.top, 40)
                    .padding(.bottom, 80)
            }
        }
        .background(BrandColors.background.ignoresSafeArea())
    }

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let plot = vod.plot, !plot.isEmpty {
                Text(plot)
                    .font(AWATypography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(maxWidth: 1200, alignment: .leading)
            }

            HStack(spacing: 28) {
                if let durationMin = vod.durationMin {
                    metaPair(label: "Duration", value: "\(durationMin) min")
                }
                if let containerExt = vod.containerExt {
                    metaPair(label: "Container", value: containerExt.uppercased())
                }
                if let tmdbId = vod.tmdbId {
                    metaPair(label: "TMDB", value: "#\(tmdbId)")
                }
            }
        }
    }

    private func metaPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(BrandColors.textMuted)
            Text(value)
                .font(AWATypography.headline)
                .foregroundStyle(BrandColors.textPrimary)
        }
    }
}
