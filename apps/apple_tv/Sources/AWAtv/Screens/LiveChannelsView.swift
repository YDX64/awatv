import SwiftUI

/// Live channels grid. Groups are rendered as horizontal carousels so the
/// Siri remote's swipe gesture can sweep through hundreds of items per
/// category without the user having to D-pad through them line by line.
struct LiveChannelsView: View {
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(PlayerStore.self) private var playerStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 56) {
                    header
                    if playlistStore.allChannels.isEmpty {
                        EmptyChannelsState()
                            .padding(.horizontal, 80)
                            .padding(.top, 40)
                    } else {
                        ForEach(groupedChannels, id: \.title) { row in
                            categoryRow(row)
                        }
                    }
                }
                .padding(.vertical, 60)
            }
            .background(BrandColors.background.ignoresSafeArea())
            .navigationDestination(isPresented: Binding(
                get: { playerStore.isPresenting },
                set: { if !$0 { playerStore.dismiss() } }
            )) {
                PlayerView()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live")
                .font(AWATypography.display)
                .foregroundStyle(BrandColors.textPrimary)
            Text("\(playlistStore.allChannels.count) channels across \(playlistStore.sources.count) playlists")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .padding(.horizontal, 80)
    }

    private func categoryRow(_ row: ChannelGroup) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(row.title)
                .font(AWATypography.title2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    ForEach(row.channels) { channel in
                        ChannelTile(channel: channel) {
                            playerStore.play(.from(channel))
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 8)
            }
            .focusSection()
        }
    }

    // MARK: - Grouping

    private struct ChannelGroup {
        let title: String
        let channels: [Channel]
    }

    private var groupedChannels: [ChannelGroup] {
        let buckets = Dictionary(grouping: playlistStore.allChannels) { channel in
            channel.groups.first ?? "All"
        }
        return buckets
            .map { ChannelGroup(title: $0.key, channels: $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

private struct EmptyChannelsState: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "tv.inset.filled")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(BrandColors.primaryLight)
            Text("No live channels yet")
                .font(AWATypography.title2)
                .foregroundStyle(BrandColors.textPrimary)
            Text("Add a playlist in Settings to get started.")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
