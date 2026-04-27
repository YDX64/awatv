import SwiftUI

/// VOD movie grid. Five columns at 1920px width feels right on a 4K TV when
/// posters are 264pt wide; SwiftUI's adaptive `LazyVGrid` handles overflow.
struct MoviesView: View {
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
                    if playlistStore.allVod.isEmpty {
                        EmptyVodState()
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                            ForEach(playlistStore.allVod) { vod in
                                NavigationLink(value: vod) {
                                    PosterCard(item: vod.posterCardItem)
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
            .navigationDestination(for: VodItem.self) { vod in
                MovieDetailView(vod: vod)
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
            Text("Movies")
                .font(AWATypography.display)
                .foregroundStyle(BrandColors.textPrimary)
            Text("\(playlistStore.allVod.count) titles ready to watch")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }
}

extension VodItem {
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

private struct EmptyVodState: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(BrandColors.primaryLight)
            Text("No movies yet")
                .font(AWATypography.title2)
                .foregroundStyle(BrandColors.textPrimary)
            Text("Connect an Xtream playlist to load your VOD library.")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
