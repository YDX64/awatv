import Foundation

/// Typed errors mirrored from `awatv_core/utils/awatv_exceptions.dart`.
enum AWANetworkError: Error, LocalizedError, Sendable {
    case auth(String)
    case http(status: Int, message: String, retryable: Bool)
    case decode(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .auth(let m): return "Authentication failed: \(m)"
        case .http(let s, let m, _): return "HTTP \(s): \(m)"
        case .decode(let m): return "Decode error: \(m)"
        case .transport(let m): return "Network error: \(m)"
        }
    }
}

/// Client for the de-facto-standard Xtream Codes player API.
///
/// Endpoint: `{server}/player_api.php?username=&password=&action=...`
///
/// Stream URL formats — kept identical to the Dart side so backends serving
/// pre-resolved URLs are interchangeable:
///
///   Live:           `{server}/{username}/{password}/{streamId}.{ext}`
///   VOD:            `{server}/movie/{username}/{password}/{streamId}.{ext}`
///   Series episode: `{server}/series/{username}/{password}/{streamId}.{ext}`
///
/// `actor` semantics give us thread-safe access to `URLSession` and
/// per-instance request memoisation when the UI hits this from multiple
/// SwiftUI tasks at once.
actor XtreamClient {
    let server: String
    let username: String
    let password: String

    private let session: URLSession
    private let decoder: JSONDecoder
    private let sourceId: String

    init(
        server: String,
        username: String,
        password: String,
        session: URLSession = .shared
    ) {
        self.server = Self.normaliseServer(server)
        self.username = username
        self.password = password
        self.session = session
        self.sourceId = "xtream:\(username)@\(URL(string: server)?.host ?? server)"

        let dec = JSONDecoder()
        // Xtream panels return Unix timestamps as strings — handled
        // per-field below; default decoder strategy stays plain.
        self.decoder = dec
    }

    // MARK: - Public API

    /// Light auth check. Hits `player_api.php` with no `action`, returning
    /// `user_info`/`server_info`. Throws `AWANetworkError.auth` on rejection.
    func authenticate() async throws -> Bool {
        let data: Data = try await get(action: nil, extra: [:])
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AWANetworkError.auth("Unexpected auth response shape")
        }
        if let userInfo = dict["user_info"] as? [String: Any] {
            let auth = userInfo["auth"]
            let status = (userInfo["status"] as? String)?.lowercased() ?? ""
            if "\(auth ?? "1")" == "0" || status == "banned" {
                throw AWANetworkError.auth("Credentials rejected by panel")
            }
        }
        return true
    }

    /// Fetch live channels and translate them into `Channel` value objects
    /// with the same id formula as the Dart parser.
    func liveChannels() async throws -> [Channel] {
        let raw = try await getJSONArray(action: "get_live_streams")
        var out: [Channel] = []
        out.reserveCapacity(raw.count)

        for entry in raw {
            guard let m = entry as? [String: Any] else { continue }
            let streamId = string(m["stream_id"]) ?? string(m["streamId"]) ?? ""
            guard !streamId.isEmpty, streamId != "null" else { continue }

            let ext: String = {
                if let typ = m["stream_type"] as? String, typ == "live",
                   let cont = m["container_extension"] as? String,
                   !cont.isEmpty
                {
                    return cont
                }
                return "ts"
            }()

            let name = (m["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Channel \(streamId)"
            let tvgId = (m["epg_channel_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let logo = (m["stream_icon"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let groupId = string(m["category_id"])

            var extras: [String: String] = [:]
            if let added = m["added"] {
                extras["added"] = "\(added)"
            }

            let url = "\(server)/\(username)/\(password)/\(streamId).\(ext)"

            out.append(
                Channel(
                    id: Channel.buildId(
                        sourceId: sourceId,
                        name: name,
                        tvgId: tvgId,
                        streamId: streamId
                    ),
                    sourceId: sourceId,
                    name: name,
                    streamUrl: url,
                    kind: .live,
                    groups: groupId.map { [$0] } ?? [],
                    tvgId: (tvgId?.isEmpty ?? true) ? nil : tvgId,
                    logoUrl: (logo?.isEmpty ?? true) ? nil : logo,
                    extras: extras
                )
            )
        }
        return out
    }

    /// VOD movie list.
    func vodItems() async throws -> [VodItem] {
        let raw = try await getJSONArray(action: "get_vod_streams")
        var out: [VodItem] = []
        out.reserveCapacity(raw.count)

        for entry in raw {
            guard let m = entry as? [String: Any] else { continue }
            let streamId = string(m["stream_id"]) ?? string(m["vod_id"]) ?? ""
            guard !streamId.isEmpty, streamId != "null" else { continue }

            let ext = (m["container_extension"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let extResolved = (ext?.isEmpty ?? true) ? "mp4" : (ext ?? "mp4")
            let title = (m["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "VOD \(streamId)"
            let poster = (m["stream_icon"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rating = double(m["rating"])
            let year = yearFromDate(string(m["releaseDate"]) ?? string(m["releasedate"]))
            let tmdbId = int(m["tmdb_id"]) ?? int(m["tmdb"])

            let url = "\(server)/movie/\(username)/\(password)/\(streamId).\(extResolved)"

            out.append(
                VodItem(
                    id: "\(sourceId)::vod::\(streamId)",
                    sourceId: sourceId,
                    title: title,
                    streamUrl: url,
                    year: year,
                    plot: (m["plot"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    posterUrl: (poster?.isEmpty ?? true) ? nil : poster,
                    rating: rating,
                    containerExt: extResolved,
                    tmdbId: tmdbId
                )
            )
        }
        return out
    }

    /// Series headers — episodes are loaded separately via
    /// ``seriesEpisodes(seriesId:)``.
    func series() async throws -> [SeriesItem] {
        let raw = try await getJSONArray(action: "get_series")
        var out: [SeriesItem] = []
        out.reserveCapacity(raw.count)

        for entry in raw {
            guard let m = entry as? [String: Any] else { continue }
            guard let seriesId = string(m["series_id"]),
                  !seriesId.isEmpty, seriesId != "null"
            else { continue }

            let title = (m["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Series \(seriesId)"
            let poster = (m["cover"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rating = double(m["rating"]) ?? double(m["rating_5based"])
            let year = yearFromDate(string(m["releaseDate"]) ?? string(m["releasedate"]))
            let tmdbId = int(m["tmdb"]) ?? int(m["tmdb_id"])

            out.append(
                SeriesItem(
                    id: "\(sourceId)::series::\(seriesId)",
                    sourceId: sourceId,
                    title: title,
                    plot: (m["plot"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    posterUrl: (poster?.isEmpty ?? true) ? nil : poster,
                    rating: rating,
                    year: year,
                    tmdbId: tmdbId
                )
            )
        }
        return out
    }

    /// Fetch episodes for a single series.
    func seriesEpisodes(seriesId: Int) async throws -> [Episode] {
        let data: Data = try await get(
            action: "get_series_info",
            extra: ["series_id": "\(seriesId)"]
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let episodes = root["episodes"] as? [String: Any]
        else { return [] }

        let seriesInternalId = "\(sourceId)::series::\(seriesId)"
        var out: [Episode] = []

        for (seasonKey, list) in episodes {
            let season = Int(seasonKey) ?? 0
            guard let arr = list as? [[String: Any]] else { continue }
            for m in arr {
                guard let id = string(m["id"]), !id.isEmpty else { continue }
                let number = int(m["episode_num"]) ?? 0
                let title = (m["title"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "S\(season)E\(number)"
                let ext = (m["container_extension"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let extResolved = (ext?.isEmpty ?? true) ? "mp4" : (ext ?? "mp4")
                let info = (m["info"] as? [String: Any]) ?? [:]
                let durationSec = int(info["duration_secs"])
                let durationMin = durationSec.map { $0 / 60 }

                out.append(
                    Episode(
                        id: "\(seriesInternalId)::s\(season)e\(number)::\(id)",
                        seriesId: seriesInternalId,
                        season: season,
                        number: number,
                        title: title,
                        streamUrl: "\(server)/series/\(username)/\(password)/\(id).\(extResolved)",
                        plot: (info["plot"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                        durationMin: durationMin,
                        posterUrl: (info["movie_image"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                        containerExt: extResolved
                    )
                )
            }
        }

        out.sort { lhs, rhs in
            if lhs.season != rhs.season { return lhs.season < rhs.season }
            return lhs.number < rhs.number
        }
        return out
    }

    /// Short EPG window (typically next 4 entries) for one stream id.
    func shortEpg(streamId: String) async throws -> [EpgProgramme] {
        let data: Data = try await get(
            action: "get_short_epg",
            extra: ["stream_id": streamId]
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listings = root["epg_listings"] as? [[String: Any]]
        else { return [] }

        var out: [EpgProgramme] = []
        for m in listings {
            guard let start = xtreamTime(m["start"]),
                  let stop = xtreamTime(m["end"])
            else { continue }
            out.append(
                EpgProgramme(
                    channelTvgId: streamId,
                    start: start,
                    stop: stop,
                    title: decodeMaybeBase64(m["title"]) ?? "",
                    description: decodeMaybeBase64(m["description"])
                )
            )
        }
        return out
    }

    // MARK: - HTTP

    private func apiURL(action: String?, extra: [String: String]) -> URL? {
        guard var components = URLComponents(string: "\(server)/player_api.php") else {
            return nil
        }
        var items = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        if let action {
            items.append(URLQueryItem(name: "action", value: action))
        }
        for (k, v) in extra {
            items.append(URLQueryItem(name: k, value: v))
        }
        components.queryItems = items
        return components.url
    }

    private func get(action: String?, extra: [String: String]) async throws -> Data {
        guard let url = apiURL(action: action, extra: extra) else {
            throw AWANetworkError.transport("Could not build URL for \(action ?? "auth")")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("AWAtv-tvOS/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw AWANetworkError.transport("Non-HTTP response")
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw AWANetworkError.auth("HTTP \(http.statusCode)")
            default:
                throw AWANetworkError.http(
                    status: http.statusCode,
                    message: "Xtream API returned \(http.statusCode)",
                    retryable: http.statusCode >= 500
                )
            }
        } catch let err as AWANetworkError {
            throw err
        } catch {
            throw AWANetworkError.transport(error.localizedDescription)
        }
    }

    private func getJSONArray(action: String) async throws -> [Any] {
        let data = try await get(action: action, extra: [:])
        let json = try JSONSerialization.jsonObject(with: data)
        return (json as? [Any]) ?? []
    }

    // MARK: - Coercions

    private static func normaliseServer(_ s: String) -> String {
        s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    private func string(_ v: Any?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    private func int(_ v: Any?) -> Int? {
        guard let v else { return nil }
        if let n = v as? Int { return n }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    private func double(_ v: Any?) -> Double? {
        guard let v else { return nil }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    private func yearFromDate(_ s: String?) -> Int? {
        guard let s, !s.isEmpty else { return nil }
        let prefix = s.prefix(4)
        return Int(prefix)
    }

    /// Xtream `start`/`end` come either as `YYYY-MM-DD HH:mm:ss` or as a
    /// unix-timestamp (string or number). Tolerate both shapes.
    private func xtreamTime(_ v: Any?) -> Date? {
        guard let v else { return nil }
        if let n = v as? NSNumber {
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        if let s = v as? String {
            if let asInt = Int(s) {
                return Date(timeIntervalSince1970: TimeInterval(asInt))
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime]
            return formatter.date(from: s)
                ?? DateFormatter.xtreamPanel.date(from: s)
        }
        return nil
    }

    /// EPG titles/descriptions are usually base64 from Xtream panels. Decode
    /// opportunistically; fall back to the raw string when it isn't valid.
    private func decodeMaybeBase64(_ v: Any?) -> String? {
        guard let raw = (v as? String), !raw.isEmpty else { return nil }
        let trimmed = raw.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        guard trimmed.count % 4 == 0,
              trimmed.range(of: "^[A-Za-z0-9+/=]+$", options: .regularExpression) != nil,
              let data = Data(base64Encoded: trimmed),
              let decoded = String(data: data, encoding: .utf8)
        else {
            return raw
        }
        return decoded
    }
}

private extension DateFormatter {
    static let xtreamPanel: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
