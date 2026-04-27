import Foundation

/// One scheduled programme on a channel — XMLTV `<programme>`.
struct EpgProgramme: Codable, Hashable, Sendable {
    let channelTvgId: String
    let start: Date
    let stop: Date
    let title: String
    let description: String?
    let category: String?

    init(
        channelTvgId: String,
        start: Date,
        stop: Date,
        title: String,
        description: String? = nil,
        category: String? = nil
    ) {
        self.channelTvgId = channelTvgId
        self.start = start
        self.stop = stop
        self.title = title
        self.description = description
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case channelTvgId = "channel_tvg_id"
        case start
        case stop
        case title
        case description
        case category
    }
}
