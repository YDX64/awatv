import SwiftUI

/// Detail screen for a series. Renders the header and a grouped season list.
///
/// Episodes are loaded lazily via `XtreamClient.seriesEpisodes` once the
/// view appears and we know the source's credentials. For M3U-only sources
/// this list will be empty — the home screen treats those as live channels.
struct SeriesDetailView: View {
    @Environment(PlayerStore.self) private var playerStore
    @Environment(PlaylistStore.self) private var playlistStore

    let series: SeriesItem

    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    private var episodesBySeason: [(Int, [Episode])] {
        let groups = Dictionary(grouping: episodes, by: { $0.season })
        return groups.keys.sorted().map { season in
            let list = (groups[season] ?? []).sorted { $0.number < $1.number }
            return (season, list)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackdropHeader(
                    title: series.title,
                    overview: series.plot,
                    backdropUrl: series.backdropUrl ?? series.posterUrl,
                    rating: series.rating,
                    year: series.year,
                    genres: series.genres
                ) {
                    HStack(spacing: 18) {
                        Button {
                            if let first = episodes.first {
                                playerStore.play(.from(first, seriesTitle: series.title))
                            }
                        } label: {
                            Label("Play first episode", systemImage: "play.fill")
                                .font(AWATypography.headline)
                                .padding(.horizontal, 36)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandColors.accent)
                        .disabled(episodes.isEmpty)
                    }
                }

                if isLoading {
                    HStack { ProgressView().tint(BrandColors.primaryLight); Text("Loading episodes…").foregroundStyle(BrandColors.textSecondary) }
                        .padding(.horizontal, 80)
                        .padding(.top, 60)
                } else if let loadError {
                    Text(loadError)
                        .font(AWATypography.body)
                        .foregroundStyle(BrandColors.pink)
                        .padding(.horizontal, 80)
                        .padding(.top, 60)
                } else {
                    seasonsList
                        .padding(.horizontal, 80)
                        .padding(.top, 40)
                        .padding(.bottom, 80)
                }
            }
        }
        .background(BrandColors.background.ignoresSafeArea())
        .task {
            await loadEpisodes()
        }
    }

    private var seasonsList: some View {
        VStack(alignment: .leading, spacing: 36) {
            ForEach(episodesBySeason, id: \.0) { (season, eps) in
                VStack(alignment: .leading, spacing: 16) {
                    Text("Season \(season)")
                        .font(AWATypography.title2)
                        .foregroundStyle(BrandColors.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 24) {
                            ForEach(eps) { ep in
                                EpisodeCard(episode: ep) {
                                    playerStore.play(.from(ep, seriesTitle: series.title))
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .focusSection()
                }
            }
        }
    }

    @MainActor
    private func loadEpisodes() async {
        guard episodes.isEmpty,
              let source = playlistStore.sources.first(where: { $0.id == series.sourceId }),
              source.kind == .xtream
        else { return }

        let credentials: (String, String)? = {
            if let user = source.username, let pass = source.password {
                return (user, pass)
            }
            return KeychainHelper.read(sourceId: source.id)
        }()
        guard let (username, password) = credentials else {
            loadError = "Missing credentials for this playlist."
            return
        }
        guard let seriesNumericId = series.id.split(separator: ":").last.flatMap({ Int($0) }) else {
            loadError = "Could not derive series id."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let client = XtreamClient(server: source.url, username: username, password: password)
            episodes = try await client.seriesEpisodes(seriesId: seriesNumericId)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Compact 16:9 card representing one episode. Smaller than `PosterCard`
/// since posters here usually come from the show's backdrop frame.
private struct EpisodeCard: View {
    let episode: Episode
    var onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(BrandColors.surface)

                    if let urlString = episode.posterUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: BrandColors.heroGradient.opacity(0.3)
                            @unknown default: BrandColors.heroGradient.opacity(0.3)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .frame(width: 360, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? BrandColors.accent : .white.opacity(0.06), lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("E\(episode.number) · \(episode.title)")
                        .font(AWATypography.headline)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(2)
                    if let durationMin = episode.durationMin {
                        Text("\(durationMin) min")
                            .font(AWATypography.caption)
                            .foregroundStyle(BrandColors.textMuted)
                    }
                }
                .padding(.horizontal, 4)
                .frame(width: 360, alignment: .leading)
            }
            .padding(8)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
        .focusGlow(isFocused, radius: 22)
    }
}
