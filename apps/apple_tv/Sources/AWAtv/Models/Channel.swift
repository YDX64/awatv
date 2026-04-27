import Foundation

/// What kind of stream a channel points to.
///
/// Matches `awatv_core/lib/src/models/channel.dart` `ChannelKind`. JSON
/// serialisation uses the lowercase Dart enum names so a future REST backend
/// can serve the same payload to both clients.
enum ChannelKind: String, Codable, Sendable {
    case live
    case vod
    case series
}

/// A single playable item.
///
/// Stable id formula matches the Dart side:
/// `"${sourceId}::${tvgId ?? streamId ?? name}"`.
struct Channel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceId: String
    let name: String
    let streamUrl: String
    let kind: ChannelKind
    let groups: [String]
    let tvgId: String?
    let logoUrl: String?
    let tmdbId: Int?
    let extras: [String: String]

    init(
        id: String,
        sourceId: String,
        name: String,
        streamUrl: String,
        kind: ChannelKind,
        groups: [String] = [],
        tvgId: String? = nil,
        logoUrl: String? = nil,
        tmdbId: Int? = nil,
        extras: [String: String] = [:]
    ) {
        self.id = id
        self.sourceId = sourceId
        self.name = name
        self.streamUrl = streamUrl
        self.kind = kind
        self.groups = groups
        self.tvgId = tvgId
        self.logoUrl = logoUrl
        self.tmdbId = tmdbId
        self.extras = extras
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId = "source_id"
        case name
        case streamUrl = "stream_url"
        case kind
        case groups
        case tvgId = "tvg_id"
        case logoUrl = "logo_url"
        case tmdbId = "tmdb_id"
        case extras
    }

    /// Compute the canonical id from its parts. Mirrors the static method on
    /// the Dart `Channel` class.
    static func buildId(
        sourceId: String,
        name: String,
        tvgId: String? = nil,
        streamId: String? = nil
    ) -> String {
        let tail: String
        if let tvgId, !tvgId.isEmpty {
            tail = tvgId
        } else if let streamId, !streamId.isEmpty {
            tail = streamId
        } else {
            tail = name
        }
        return "\(sourceId)::\(tail)"
    }
}
