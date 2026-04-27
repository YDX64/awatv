import SwiftUI

/// Global search across all sources. Uses tvOS 17's `searchable` modifier
/// which renders the system on-screen keyboard automatically when the field
/// is focused.
struct SearchView: View {
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(PlayerStore.self) private var playerStore
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    Text("Search")
                        .font(AWATypography.display)
                        .foregroundStyle(BrandColors.textPrimary)
                        .padding(.horizontal, 80)

                    if matchingChannels.isEmpty
                        && matchingMovies.isEmpty
                        && matchingSeries.isEmpty
                    {
                        emptyState
                    } else {
                        if !matchingChannels.isEmpty {
                            section(title: "Channels") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 28) {
                                        ForEach(matchingChannels) { channel in
                                            ChannelTile(channel: channel) {
                                                playerStore.play(.from(channel))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 80)
                                    .padding(.vertical, 8)
                                }
                            }
                        }

                        if !matchingMovies.isEmpty {
                            section(title: "Movies") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 28) {
                                        ForEach(matchingMovies) { vod in
                                            NavigationLink(value: vod) {
                                                PosterCard(item: vod.posterCardItem)
                                            }
                                            .buttonStyle(.card)
                                        }
                                    }
                                    .padding(.horizontal, 80)
                                    .padding(.vertical, 8)
                                }
                            }
                        }

                        if !matchingSeries.isEmpty {
                            section(title: "Series") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 28) {
                                        ForEach(matchingSeries) { item in
                                            NavigationLink(value: item) {
                                                PosterCard(item: item.posterCardItem)
                                            }
                                            .buttonStyle(.card)
                                        }
                                    }
                                    .padding(.horizontal, 80)
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 60)
            }
            .background(BrandColors.background.ignoresSafeArea())
            .searchable(text: $query, prompt: "Find a channel, movie or series")
            .navigationDestination(for: VodItem.self) { vod in
                MovieDetailView(vod: vod)
            }
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

    @ViewBuilder
    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(AWATypography.title2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, 80)
            content()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(BrandColors.primaryLight)
            Text(query.isEmpty ? "Type to search" : "No results for \"\(query)\"")
                .font(AWATypography.title2)
                .foregroundStyle(BrandColors.textPrimary)
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 80)
    }

    // MARK: - Filters

    private var lowerQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var matchingChannels: [Channel] {
        guard !lowerQuery.isEmpty else { return [] }
        return playlistStore.allChannels.filter {
            $0.name.lowercased().contains(lowerQuery)
                || $0.groups.contains(where: { $0.lowercased().contains(lowerQuery) })
        }
    }

    private var matchingMovies: [VodItem] {
        guard !lowerQuery.isEmpty else { return [] }
        return playlistStore.allVod.filter {
            $0.title.lowercased().contains(lowerQuery)
                || $0.genres.contains(where: { $0.lowercased().contains(lowerQuery) })
        }
    }

    private var matchingSeries: [SeriesItem] {
        guard !lowerQuery.isEmpty else { return [] }
        return playlistStore.allSeries.filter {
            $0.title.lowercased().contains(lowerQuery)
                || $0.genres.contains(where: { $0.lowercased().contains(lowerQuery) })
        }
    }
}

private extension VodItem {
    var posterCardItem: PosterCard.Item {
        PosterCard.Item(id: id, title: title, posterUrl: posterUrl, rating: rating, year: year)
    }
}

private extension SeriesItem {
    var posterCardItem: PosterCard.Item {
        PosterCard.Item(id: id, title: title, posterUrl: posterUrl, rating: rating, year: year)
    }
}
