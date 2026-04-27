import Foundation
import Observation

/// What the player is currently doing. Covers the small number of states the
/// `PlayerView` needs to drive UI feedback (skeletons, error retries).
enum PlayerStatus: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case failed(String)
}

/// A normalised view of the item the player is about to play. We don't pass
/// raw `Channel`/`VodItem`/`Episode` so the view doesn't need to switch on
/// kind in five places.
struct PlayableMedia: Hashable, Sendable {
    enum Kind: Sendable { case live, movie, episode }

    let id: String
    let title: String
    let subtitle: String?
    let posterUrl: String?
    let streamUrl: String
    let kind: Kind

    static func from(_ channel: Channel) -> PlayableMedia {
        PlayableMedia(
            id: channel.id,
            title: channel.name,
            subtitle: channel.groups.joined(separator: " / "),
            posterUrl: channel.logoUrl,
            streamUrl: channel.streamUrl,
            kind: .live
        )
    }

    static func from(_ vod: VodItem) -> PlayableMedia {
        let yearLabel = vod.year.map { "\($0)" }
        let parts = [yearLabel, vod.genres.joined(separator: ", ")].compactMap { $0?.isEmpty == false ? $0 : nil }
        return PlayableMedia(
            id: vod.id,
            title: vod.title,
            subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
            posterUrl: vod.posterUrl,
            streamUrl: vod.streamUrl,
            kind: .movie
        )
    }

    static func from(_ episode: Episode, seriesTitle: String) -> PlayableMedia {
        PlayableMedia(
            id: episode.id,
            title: "\(seriesTitle) — \(episode.title)",
            subtitle: "Season \(episode.season), Episode \(episode.number)",
            posterUrl: episode.posterUrl,
            streamUrl: episode.streamUrl,
            kind: .episode
        )
    }
}

/// State container for the modal player. The actual `AVPlayer` lifecycle is
/// owned by `PlayerView` (which is a `UIViewControllerRepresentable`); this
/// store just exposes the navigation flag and the active media.
@Observable
@MainActor
final class PlayerStore {
    var media: PlayableMedia?
    var status: PlayerStatus = .idle
    var isPresenting: Bool = false

    func play(_ media: PlayableMedia) {
        self.media = media
        self.status = .loading
        self.isPresenting = true
    }

    func dismiss() {
        self.isPresenting = false
        self.media = nil
        self.status = .idle
    }
}
