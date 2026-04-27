import Foundation

/// On-demand movie. Matches `awatv_core` `VodItem`.
struct VodItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceId: String
    let title: String
    let streamUrl: String
    let genres: [String]
    let year: Int?
    let plot: String?
    let posterUrl: String?
    let backdropUrl: String?
    let rating: Double?
    let durationMin: Int?
    let containerExt: String?
    let tmdbId: Int?

    init(
        id: String,
        sourceId: String,
        title: String,
        streamUrl: String,
        genres: [String] = [],
        year: Int? = nil,
        plot: String? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        rating: Double? = nil,
        durationMin: Int? = nil,
        containerExt: String? = nil,
        tmdbId: Int? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.streamUrl = streamUrl
        self.genres = genres
        self.year = year
        self.plot = plot
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.rating = rating
        self.durationMin = durationMin
        self.containerExt = containerExt
        self.tmdbId = tmdbId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId = "source_id"
        case title
        case streamUrl = "stream_url"
        case genres
        case year
        case plot
        case posterUrl = "poster_url"
        case backdropUrl = "backdrop_url"
        case rating
        case durationMin = "duration_min"
        case containerExt = "container_ext"
        case tmdbId = "tmdb_id"
    }
}
