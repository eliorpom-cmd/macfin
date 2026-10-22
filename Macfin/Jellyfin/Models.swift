import Foundation

struct Item: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    /// "Movie", "Series", "Season" or "Episode".
    let type: String?
    let seriesId: String?
    let seriesName: String?
    let seasonId: String?
    /// Season number of an episode.
    let parentIndexNumber: Int?
    /// Episode number within its season, or season number for a season.
    let indexNumber: Int?
    let parentBackdropItemId: String?
    let parentBackdropImageTags: [String]?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let overview: String?
    let officialRating: String?
    let communityRating: Double?
    let genres: [String]?
    let dateCreated: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    /// mediaSourceId → width → tiles description.
    let trickplay: [String: [String: TrickplayInfo]]?
    var userData: UserData?

    /// Smallest available trickplay resolution for the default media source.
    var trickplayInfo: TrickplayInfo? {
        (trickplay?[id] ?? trickplay?.values.first)?.values.min { $0.width < $1.width }
    }

    var isSeries: Bool { type == "Series" }
    var isEpisode: Bool { type == "Episode" }

    /// "S1 · E2" for an episode.
    var episodeCode: String? {
        guard isEpisode, let episode = indexNumber else { return nil }
        return "S\(parentIndexNumber ?? 1) · E\(episode)"
    }

    /// Show name for an episode, its own name otherwise.
    var displayTitle: String { isEpisode ? (seriesName ?? name) : name }

    /// "S1 · E2 · Episode title" for an episode, nil otherwise.
    var episodeLine: String? { episodeCode.map { "\($0) · \(name)" } }

    var positionTicks: Int64 { userData?.playbackPositionTicks ?? 0 }
    var isPlayed: Bool { userData?.played ?? false }
    var canResume: Bool { positionTicks > 0 && !isPlayed }

    var progress: Double? {
        guard canResume, let total = runTimeTicks, total > 0 else { return nil }
        return Double(positionTicks) / Double(total)
    }

    /// Image tag lookup that tolerates the key-casing applied by the decoder.
    func hasImage(_ type: String) -> Bool {
        let tags = imageTags ?? [:]
        return tags[type] != nil || tags[type.prefix(1).lowercased() + type.dropFirst()] != nil
    }

    var hasBackdrop: Bool { !(backdropImageTags ?? []).isEmpty }

    var runtimeText: String? { runTimeTicks.map { Self.duration(ticks: $0) } }

    var remainingText: String? {
        guard canResume, let total = runTimeTicks else { return nil }
        let duration = Self.duration(ticks: max(total - positionTicks, 0))
        return String(localized: "\(duration) left")
    }

    var metaLine: String {
        var parts: [String] = []
        if let episodeLine { parts.append(episodeLine) }
        if let year = productionYear { parts.append(String(year)) }
        if !isSeries, let runtime = runtimeText { parts.append(runtime) }
        if let genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        if let rating = officialRating { parts.append(rating.replacingOccurrences(of: "FR-", with: "")) }
        return parts.joined(separator: " · ")
    }

    static func duration(ticks: Int64) -> String {
        let minutes = Int(ticks / 600_000_000)
        if minutes < 60 { return String(localized: "\(max(minutes, 1)) min") }
        return String(localized: "\(minutes / 60) hr \(minutes % 60) min")
    }
}

/// Jellyfin trickplay sheet: thumbnails every `interval` ms, packed in tileWidth × tileHeight JPEG grids.
struct TrickplayInfo: Decodable, Hashable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int
}

struct UserData: Decodable, Hashable {
    var playbackPositionTicks: Int64
    var played: Bool
}

struct ItemsPage: Decodable {
    let items: [Item]
}

struct AuthResult: Decodable {
    struct User: Decodable { let id: String; let name: String }
    let accessToken: String
    let user: User
}

struct Credentials: Codable {
    var server: URL
    var token: String
    var userId: String
    var userName: String
}
