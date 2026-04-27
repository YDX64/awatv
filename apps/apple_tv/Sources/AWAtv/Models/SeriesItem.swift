import Foundation

/// A TV series header. Episode lists are loaded on-demand.
struct SeriesItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceId: String
    let title: String
    let seasons: [Int]
    let genres: [String]
    let plot: String?
    let posterUrl: String?
    let backdropUrl: String?
    let rating: Double?
    let year: Int?
    let tmdbId: Int?

    init(
        id: String,
        sourceId: String,
        title: String,
        seasons: [Int] = [],
        genres: [String] = [],
        plot: String? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        rating: Double? = nil,
        year: Int? = nil,
        tmdbId: Int? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.seasons = seasons
        self.genres = genres
        self.plot = plot
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.rating = rating
        self.year = year
        self.tmdbId = tmdbId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId = "source_id"
        case title
        case seasons
        case genres
        case plot
        case posterUrl = "poster_url"
        case backdropUrl = "backdrop_url"
        case rating
        case year
        case tmdbId = "tmdb_id"
    }
}
