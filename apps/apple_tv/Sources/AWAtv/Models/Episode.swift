import Foundation

/// One episode inside a `SeriesItem`.
struct Episode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let seriesId: String
    let season: Int
    let number: Int
    let title: String
    let streamUrl: String
    let plot: String?
    let durationMin: Int?
    let posterUrl: String?
    let containerExt: String?

    init(
        id: String,
        seriesId: String,
        season: Int,
        number: Int,
        title: String,
        streamUrl: String,
        plot: String? = nil,
        durationMin: Int? = nil,
        posterUrl: String? = nil,
        containerExt: String? = nil
    ) {
        self.id = id
        self.seriesId = seriesId
        self.season = season
        self.number = number
        self.title = title
        self.streamUrl = streamUrl
        self.plot = plot
        self.durationMin = durationMin
        self.posterUrl = posterUrl
        self.containerExt = containerExt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case seriesId = "series_id"
        case season
        case number
        case title
        case streamUrl = "stream_url"
        case plot
        case durationMin = "duration_min"
        case posterUrl = "poster_url"
        case containerExt = "container_ext"
    }
}
