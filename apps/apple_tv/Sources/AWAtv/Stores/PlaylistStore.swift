import Foundation
import Observation
import Security

/// Mirror of `awatv_core`'s `PlaylistService` — owns the user's playlist
/// sources and the channels/VOD/series cached for each one.
///
/// Storage strategy for the scaffold:
/// - Non-sensitive `PlaylistSource` rows persist to `UserDefaults`.
/// - Username + password persist to the iOS / tvOS Keychain via
///   `KeychainHelper`.
///
/// When the Phase 5 backend ships, replace the per-source `XtreamClient`
/// instantiation in `refresh(_:)` with a REST call to
/// `https://api.awatv.app/v1/sources/{id}/snapshot` returning the same
/// JSON shape these models decode (see `Channel.CodingKeys` etc.).
@Observable
@MainActor
final class PlaylistStore {
    private(set) var sources: [PlaylistSource] = []
    private(set) var channelsBySource: [String: [Channel]] = [:]
    private(set) var vodBySource: [String: [VodItem]] = [:]
    private(set) var seriesBySource: [String: [SeriesItem]] = [:]
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    private let storage: PlaylistPersistence

    init(storage: PlaylistPersistence = UserDefaultsPlaylistPersistence()) {
        self.storage = storage
    }

    /// Called once at app launch from `ContentView.task` — restores stored
    /// sources and triggers a background refresh of each.
    func bootstrap() async {
        sources = storage.loadSources()
        for source in sources {
            await refresh(sourceId: source.id, silent: true)
        }
    }

    /// All channels across all sources, deduped by id.
    var allChannels: [Channel] {
        var seen: Set<String> = []
        var out: [Channel] = []
        for s in sources {
            for c in channelsBySource[s.id] ?? [] where !seen.contains(c.id) {
                seen.insert(c.id)
                out.append(c)
            }
        }
        return out
    }

    var allVod: [VodItem] {
        sources.flatMap { vodBySource[$0.id] ?? [] }
    }

    var allSeries: [SeriesItem] {
        sources.flatMap { seriesBySource[$0.id] ?? [] }
    }

    func channels(for sourceId: String) -> [Channel] {
        channelsBySource[sourceId] ?? []
    }

    /// Add a new playlist and immediately refresh it. Credentials are
    /// stored to Keychain; the in-memory copy is kept inside the
    /// `PlaylistSource` for the current session only.
    @discardableResult
    func add(_ source: PlaylistSource) async -> Result<Void, Error> {
        sources.append(source)
        storage.save(sources: sources)
        if let user = source.username, let pass = source.password {
            KeychainHelper.set(user: user, password: pass, sourceId: source.id)
        }
        await refresh(sourceId: source.id, silent: false)
        return lastError.map { .failure(AWANetworkError.transport($0)) } ?? .success(())
    }

    func remove(_ source: PlaylistSource) {
        sources.removeAll { $0.id == source.id }
        channelsBySource.removeValue(forKey: source.id)
        vodBySource.removeValue(forKey: source.id)
        seriesBySource.removeValue(forKey: source.id)
        KeychainHelper.delete(sourceId: source.id)
        storage.save(sources: sources)
    }

    func refresh(sourceId: String, silent: Bool = false) async {
        guard let source = sources.first(where: { $0.id == sourceId }) else { return }
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }

        do {
            switch source.kind {
            case .xtream:
                try await refreshXtream(source)
            case .m3u:
                try await refreshM3U(source)
            }
            lastError = nil
            updateLastSync(for: source.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Internal refreshers

    private func refreshXtream(_ source: PlaylistSource) async throws {
        let credentials = source.username.flatMap { user -> (String, String)? in
            if let pass = source.password { return (user, pass) }
            return KeychainHelper.read(sourceId: source.id)
        }
        guard let (username, password) = credentials else {
            throw AWANetworkError.auth("No Xtream credentials stored for \(source.name)")
        }

        let client = XtreamClient(server: source.url, username: username, password: password)
        let (live, vod, series) = try await loadAll(client: client)

        channelsBySource[source.id] = live
        vodBySource[source.id] = vod
        seriesBySource[source.id] = series
    }

    /// Run the three Xtream calls in parallel — same approach the Dart
    /// `PlaylistService` takes via `Future.wait`.
    private func loadAll(client: XtreamClient) async throws -> ([Channel], [VodItem], [SeriesItem]) {
        async let live = client.liveChannels()
        async let vod = client.vodItems()
        async let series = client.series()
        return try await (live, vod, series)
    }

    private func refreshM3U(_ source: PlaylistSource) async throws {
        guard let url = URL(string: source.url) else {
            throw AWANetworkError.transport("Invalid M3U URL")
        }
        let downloader = M3UDownloader()
        let channels = try await downloader.fetch(url: url, sourceId: source.id)
        channelsBySource[source.id] = channels
    }

    private func updateLastSync(for sourceId: String) {
        if let idx = sources.firstIndex(where: { $0.id == sourceId }) {
            sources[idx].lastSyncAt = Date()
            storage.save(sources: sources)
        }
    }
}

// MARK: - Persistence

protocol PlaylistPersistence: Sendable {
    func loadSources() -> [PlaylistSource]
    func save(sources: [PlaylistSource])
}

struct UserDefaultsPlaylistPersistence: PlaylistPersistence {
    private let key = "awatv.playlist_sources.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSources() -> [PlaylistSource] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PlaylistSource].self, from: data)) ?? []
    }

    func save(sources: [PlaylistSource]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var sanitized = sources
        for i in sanitized.indices {
            // Never write credentials to UserDefaults — they live in Keychain.
            sanitized[i].username = nil
            sanitized[i].password = nil
        }
        if let data = try? encoder.encode(sanitized) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Keychain

enum KeychainHelper {
    private static let service = "app.awatv.tvos.xtream"

    static func set(user: String, password: String, sourceId: String) {
        let payload = "\(user)\u{1F}\(password)".data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceId
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = payload
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(sourceId: String) -> (String, String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceId,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        let parts = str.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    static func delete(sourceId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceId
        ]
        SecItemDelete(query as CFDictionary)
    }
}
