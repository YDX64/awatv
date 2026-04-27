import SwiftUI

/// Series grid. Same column treatment as the Movies grid; tapping a poster
/// pushes a `SeriesDetailView` that lazily loads episodes.
struct SeriesView: View {
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(PlayerStore.self) private var playerStore

    private let columns: [GridItem] = Array(
        repeating: GridItem(.fixed(280), spacing: 32),
        count: 5
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    if playlistStore.allSeries.isEmpty {
                        EmptySeriesState()
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                            ForEach(playlistStore.allSeries) { series in
                                NavigationLink(value: series) {
                                    PosterCard(item: series.posterCardItem)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            }
            .background(BrandColors.background.ignoresSafeArea())
            .navigationDestination(for: SeriesItem.self) { item in
                SeriesDetailView(series: item)
            }
            .navigationDestination(isPresented: Binding(
                get: { playerStore.isPresenting },
                set: { if !$0 { playerStore.dismiss() } }
            )) {
                PlayerView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Series")
                .font(AWATypography.display)
                .foregroundStyle(BrandColors.textPrimary)
            Text("\(playlistStore.allSeries.count) shows tracked")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }
}

extension SeriesItem {
    fileprivate var posterCardItem: PosterCard.Item {
        PosterCard.Item(
            id: id,
            title: title,
            posterUrl: posterUrl,
            rating: rating,
            year: year
        )
    }
}

private struct EmptySeriesState: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(BrandColors.primaryLight)
            Text("No series yet")
                .font(AWATypography.title2)
                .foregroundStyle(BrandColors.textPrimary)
            Text("Series appear after you sync an Xtream playlist with TV content.")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
