import Foundation

/// Kind of upstream playlist provider.
enum PlaylistKind: String, Codable, Sendable {
    case m3u
    case xtream
}

/// A user-added playlist source.
///
/// Credentials in this struct are passed in-memory only. The `PlaylistStore`
/// persists non-sensitive fields to `UserDefaults` and writes
/// username/password to the Keychain via `KeychainHelper`.
struct PlaylistSource: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: PlaylistKind
    let url: String
    let addedAt: Date
    var username: String?
    var password: String?
    var epgUrl: String?
    var lastSyncAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: PlaylistKind,
        url: String,
        addedAt: Date = Date(),
        username: String? = nil,
        password: String? = nil,
        epgUrl: String? = nil,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.addedAt = addedAt
        self.username = username
        self.password = password
        self.epgUrl = epgUrl
        self.lastSyncAt = lastSyncAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case url
        case addedAt = "added_at"
        case username
        case password
        case epgUrl = "epg_url"
        case lastSyncAt = "last_sync_at"
    }
}
