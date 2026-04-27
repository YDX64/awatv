import Foundation

/// Parser for M3U / M3U8 IPTV playlists.
///
/// Mirrors the behaviour of `awatv_core`'s `M3uParser`:
/// - Tolerates missing `#EXTM3U` header.
/// - Reads `#EXTINF:duration tvg-id="..." tvg-logo="..." group-title="..."`
///   into structured fields, with extras kept in the channel's `extras` map.
/// - Recognises `#EXTGRP:`, `#EXTVLCOPT:`, `#KODIPROP:`.
/// - Skips malformed lines with a console warning.
enum M3UParser {
    /// Parse a body into channels. `sourceId` is the parent
    /// `PlaylistSource.id` and is used to compose stable channel ids.
    static func parse(_ body: String, sourceId: String) throws -> [Channel] {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty { return [] }

        let lines = trimmedBody.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        var sawExtinf = false
        var pending: PendingChannel?
        var lineNumber = 0
        var result: [Channel] = []

        for raw in lines {
            lineNumber += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTM3U") {
                continue
            }

            if line.hasPrefix("#EXTINF") {
                sawExtinf = true
                pending = parseExtinf(line)
                continue
            }

            if line.hasPrefix("#EXTGRP:") {
                let group = line.replacingOccurrences(of: "#EXTGRP:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let p = pending, !group.isEmpty {
                    var copy = p
                    copy.groups.append(contentsOf: splitGroups(group))
                    pending = copy
                }
                continue
            }

            if line.hasPrefix("#EXTVLCOPT:") {
                let kv = String(line.dropFirst("#EXTVLCOPT:".count))
                    .trimmingCharacters(in: .whitespaces)
                if let p = pending,
                   let eq = kv.firstIndex(of: "="), eq != kv.startIndex
                {
                    let key = String(kv[..<eq]).trimmingCharacters(in: .whitespaces)
                    let value = String(kv[kv.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    var copy = p
                    copy.extras[key] = value
                    pending = copy
                }
                continue
            }

            if line.hasPrefix("#KODIPROP:") {
                let kv = String(line.dropFirst("#KODIPROP:".count))
                    .trimmingCharacters(in: .whitespaces)
                if let p = pending,
                   let eq = kv.firstIndex(of: "="), eq != kv.startIndex
                {
                    let key = "kodi." + String(kv[..<eq]).trimmingCharacters(in: .whitespaces)
                    let value = String(kv[kv.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    var copy = p
                    copy.extras[key] = value
                    pending = copy
                }
                continue
            }

            if line.hasPrefix("#") {
                continue
            }

            // Non-comment line is the URL for the most recent EXTINF.
            if pending == nil {
                if let bareChannel = channelFromBareUrl(String(line), sourceId: sourceId) {
                    result.append(bareChannel)
                }
                continue
            }

            if let p = pending,
               let channel = makeChannel(p, url: String(line), sourceId: sourceId)
            {
                result.append(channel)
            }
            pending = nil
        }

        if result.isEmpty && !sawExtinf {
            throw AWANetworkError.decode("No #EXTINF entries and no playable URLs found")
        }
        return result
    }

    // MARK: - Internals

    private struct PendingChannel {
        var title: String
        var tvgId: String?
        var logoUrl: String?
        var groups: [String]
        var extras: [String: String]
    }

    private static let consumedAttrs: Set<String> = [
        "tvg-id", "tvg-logo", "tvg-name", "logo", "group-title"
    ]

    private static func parseExtinf(_ line: String) -> PendingChannel? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let body = String(line[line.index(after: colon)...])
        guard let commaIdx = topLevelCommaIndex(in: body) else { return nil }

        let head = String(body[..<commaIdx])
        let title = String(body[body.index(after: commaIdx)...])
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        let attrs = parseAttrs(head)
        var groups: [String] = []
        if let g = attrs["group-title"], !g.isEmpty {
            groups.append(contentsOf: splitGroups(g))
        }
        var extras: [String: String] = [:]
        for (k, v) in attrs where !consumedAttrs.contains(k) {
            extras[k] = v
        }

        return PendingChannel(
            title: title,
            tvgId: attrs["tvg-id"],
            logoUrl: attrs["tvg-logo"] ?? attrs["logo"],
            groups: groups,
            extras: extras
        )
    }

    private static func parseAttrs(_ head: String) -> [String: String] {
        var out: [String: String] = [:]
        let chars = Array(head)
        var i = 0
        let n = chars.count

        // Skip leading duration token.
        while i < n && chars[i] != " " && chars[i] != "\t" {
            i += 1
        }

        while i < n {
            while i < n && (chars[i] == " " || chars[i] == "\t") { i += 1 }
            if i >= n { break }

            let keyStart = i
            while i < n && chars[i] != "=" && chars[i] != " " && chars[i] != "\t" {
                i += 1
            }
            if i >= n || chars[i] != "=" { break }
            let key = String(chars[keyStart..<i])
            i += 1

            var value = ""
            if i < n && chars[i] == "\"" {
                i += 1
                let valStart = i
                while i < n && chars[i] != "\"" { i += 1 }
                value = String(chars[valStart..<i])
                if i < n { i += 1 }
            } else {
                let valStart = i
                while i < n && chars[i] != " " && chars[i] != "\t" { i += 1 }
                value = String(chars[valStart..<i])
            }
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    private static func topLevelCommaIndex(in s: String) -> String.Index? {
        var inQuote = false
        var idx = s.startIndex
        while idx < s.endIndex {
            let c = s[idx]
            if c == "\"" { inQuote.toggle() }
            if c == "," && !inQuote { return idx }
            idx = s.index(after: idx)
        }
        return nil
    }

    private static func splitGroups(_ raw: String) -> [String] {
        raw
            .split { ch in ch == "/" || ch == ";" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func looksLikeURL(_ s: String) -> Bool {
        let lc = s.lowercased()
        return lc.hasPrefix("http://")
            || lc.hasPrefix("https://")
            || lc.hasPrefix("rtmp://")
            || lc.hasPrefix("rtsp://")
            || lc.hasPrefix("udp://")
            || lc.hasPrefix("rtp://")
    }

    private static func filenameFromURL(_ url: String) -> String {
        let stripped: String = {
            if let q = url.firstIndex(of: "?") {
                return String(url[..<q])
            }
            return url
        }()
        if let slash = stripped.lastIndex(of: "/") {
            let name = String(stripped[stripped.index(after: slash)...])
            return name.isEmpty ? url : name
        }
        return stripped
    }

    private static func channelFromBareUrl(_ url: String, sourceId: String) -> Channel? {
        guard looksLikeURL(url) else { return nil }
        let name = filenameFromURL(url)
        return Channel(
            id: Channel.buildId(sourceId: sourceId, name: name),
            sourceId: sourceId,
            name: name,
            streamUrl: url,
            kind: .live
        )
    }

    private static func makeChannel(
        _ p: PendingChannel,
        url: String,
        sourceId: String
    ) -> Channel? {
        guard !url.isEmpty, looksLikeURL(url) else { return nil }
        return Channel(
            id: Channel.buildId(sourceId: sourceId, name: p.title, tvgId: p.tvgId),
            sourceId: sourceId,
            name: p.title,
            streamUrl: url,
            kind: inferKind(url: url, groups: p.groups),
            groups: p.groups,
            tvgId: (p.tvgId?.isEmpty ?? true) ? nil : p.tvgId,
            logoUrl: (p.logoUrl?.isEmpty ?? true) ? nil : p.logoUrl,
            extras: p.extras
        )
    }

    private static func inferKind(url: String, groups: [String]) -> ChannelKind {
        let lcGroups = groups.map { $0.lowercased() }
        let lcUrl = url.lowercased()
        if lcGroups.contains(where: { $0.contains("vod") || $0.contains("movie") }) {
            return .vod
        }
        if lcGroups.contains(where: { $0.contains("series") }) {
            return .series
        }
        if lcUrl.contains("/movie/") { return .vod }
        if lcUrl.contains("/series/") { return .series }
        return .live
    }
}

/// Convenience network fetcher that downloads the M3U body and parses it.
struct M3UDownloader {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(url: URL, sourceId: String) async throws -> [Channel] {
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        req.setValue("AWAtv-tvOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AWANetworkError.http(
                status: status,
                message: "M3U fetch failed",
                retryable: status >= 500
            )
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        return try M3UParser.parse(body, sourceId: sourceId)
    }
}
