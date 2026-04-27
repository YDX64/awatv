import Foundation

/// Minimal TMDB v3 client used to enrich VOD and series with posters,
/// backdrops and ratings. Wider parity with `awatv_core/MetadataService`
/// will land once the Phase 5 backend exposes a single enrichment endpoint;
/// for the scaffold we hit TMDB directly when an `apiKey` is provided.
actor TmdbClient {
    static let imageBaseUrl = "https://image.tmdb.org/t/p"
    static let apiBaseUrl = "https://api.themoviedb.org/3"

    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private var cache: [String: TmdbResult] = [:]

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    /// Search for a movie by title (and optional year). Cached in-memory.
    func movie(title: String, year: Int? = nil) async throws -> TmdbResult? {
        guard !apiKey.isEmpty else { return nil }
        let key = "movie:\(title.lowercased())|\(year.map(String.init) ?? "")"
        if let hit = cache[key] { return hit }

        var components = URLComponents(string: "\(Self.apiBaseUrl)/search/movie")!
        var q = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        if let year { q.append(URLQueryItem(name: "primary_release_year", value: "\(year)")) }
        components.queryItems = q

        guard let url = components.url else { return nil }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }

        let envelope = try decoder.decode(TmdbSearchEnvelope.self, from: data)
        guard let first = envelope.results.first else { return nil }
        cache[key] = first
        return first
    }

    /// Resolve a poster URL for a relative TMDB path.
    static func posterURL(path: String?, size: PosterSize = .w500) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "\(imageBaseUrl)/\(size.rawValue)\(path)")
    }

    /// Resolve a backdrop URL for a relative TMDB path.
    static func backdropURL(path: String?, size: BackdropSize = .w1280) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "\(imageBaseUrl)/\(size.rawValue)\(path)")
    }

    enum PosterSize: String { case w185, w342, w500, original }
    enum BackdropSize: String { case w780, w1280, original }
}

struct TmdbResult: Codable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let firstAirDate: String?
}

private struct TmdbSearchEnvelope: Codable {
    let page: Int
    let results: [TmdbResult]
    let totalResults: Int?
    let totalPages: Int?
}
