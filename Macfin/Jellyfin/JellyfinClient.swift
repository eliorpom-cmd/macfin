import Foundation

enum JellyfinError: LocalizedError {
    case unauthorized
    case status(Int)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .unauthorized: String(localized: "The user name or password is incorrect.")
        case .status(let code): String(localized: "The server returned an error (\(code)).")
        case .unreachable: String(localized: "Can’t reach the server. Make sure Jellyfin is running on this Mac.")
        }
    }
}

enum PlaybackEvent: String {
    case start = "/Sessions/Playing"
    case progress = "/Sessions/Playing/Progress"
    case stopped = "/Sessions/Playing/Stopped"
}

/// Minimal Jellyfin REST client: library, images, direct-play stream and progress reporting.
struct JellyfinClient {
    let server: URL
    var credentials: Credentials?

    init(server: URL) { self.server = server }
    init(credentials: Credentials) { server = credentials.server; self.credentials = credentials }

    private static let deviceId: String = {
        let key = "deviceId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Jellyfin uses PascalCase keys; Swift properties are camelCase.
        decoder.keyDecodingStrategy = .custom { path in
            let key = path.last!.stringValue
            return AnyKey(key.prefix(1).lowercased() + key.dropFirst())
        }
        return decoder
    }()

    private var authorization: String {
        var header = #"MediaBrowser Client="Macfin", Device="Mac", DeviceId="\#(Self.deviceId)", Version="\#(Self.version)""#
        if let token = credentials?.token { header += #", Token="\#(token)""# }
        return header
    }

    private var userId: String { credentials?.userId ?? "" }

    // MARK: Requests

    func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: server.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: url(path, query), timeoutInterval: 15)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw JellyfinError.unreachable }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw JellyfinError.unauthorized }
        guard (200..<300).contains(code) else { throw JellyfinError.status(code) }
        return data
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:], as type: T.Type) async throws -> T {
        try Self.decoder.decode(T.self, from: try await send("GET", path, query: query))
    }

    // MARK: Session

    func authenticate(username: String, password: String) async throws -> Credentials {
        let data = try await send("POST", "/Users/AuthenticateByName", body: ["Username": username, "Pw": password])
        let result = try Self.decoder.decode(AuthResult.self, from: data)
        return Credentials(server: server, token: result.accessToken, userId: result.user.id, userName: result.user.name)
    }

    /// Approves a Quick Connect code shown by another device, signing it in as the current user.
    func authorizeQuickConnect(code: String) async throws {
        try await send("POST", "/QuickConnect/Authorize", query: ["code": code, "userId": userId])
    }

    func logout() async { _ = try? await send("POST", "/Sessions/Logout") }

    // MARK: Library

    private static let fields = "Overview,Genres,DateCreated,Trickplay,ParentId"

    func movies() async throws -> [Item] {
        try await get("/Items", ["userId": userId, "IncludeItemTypes": "Movie", "Recursive": "true",
                                 "SortBy": "SortName", "Fields": Self.fields], as: ItemsPage.self).items
    }

    func series() async throws -> [Item] {
        try await get("/Items", ["userId": userId, "IncludeItemTypes": "Series", "Recursive": "true",
                                 "SortBy": "SortName", "Fields": Self.fields], as: ItemsPage.self).items
    }

    func seasons(of series: Item) async throws -> [Item] {
        try await get("/Shows/\(series.id)/Seasons", ["userId": userId, "Fields": Self.fields], as: ItemsPage.self).items
    }

    /// Every episode of a show in airing order, all seasons together.
    func episodes(ofSeries seriesId: String) async throws -> [Item] {
        try await get("/Shows/\(seriesId)/Episodes", ["userId": userId, "Fields": Self.fields], as: ItemsPage.self).items
    }

    /// Next unwatched episode of each show being followed.
    func nextUp() async throws -> [Item] {
        try await get("/Shows/NextUp", ["userId": userId, "Limit": "20", "Fields": Self.fields], as: ItemsPage.self).items
    }

    func resume() async throws -> [Item] {
        try await get("/UserItems/Resume", ["userId": userId, "MediaTypes": "Video", "Limit": "20",
                                            "Fields": Self.fields], as: ItemsPage.self).items
    }

    func latest() async throws -> [Item] {
        try await get("/Items/Latest", ["userId": userId, "IncludeItemTypes": "Movie", "Limit": "16",
                                        "Fields": Self.fields], as: [Item].self)
    }

    func setPlayed(_ item: Item, _ played: Bool) async throws {
        try await send(played ? "POST" : "DELETE", "/UserPlayedItems/\(item.id)", query: ["userId": userId])
    }

    // MARK: Media

    func imageURL(_ item: Item, _ type: String, width: Int) -> URL {
        url("/Items/\(item.id)/Images/\(type)", ["maxWidth": String(width), "quality": "90"])
    }

    /// Wide background: the item's backdrop, else its show's for an episode, else its landscape still.
    func backdropURL(_ item: Item, width: Int) -> URL {
        if item.hasBackdrop { return imageURL(item, "Backdrop", width: width) }
        if let parent = item.parentBackdropItemId, !(item.parentBackdropImageTags ?? []).isEmpty {
            return url("/Items/\(parent)/Images/Backdrop", ["maxWidth": String(width), "quality": "90"])
        }
        return stillURL(item, width: width)
    }

    /// Landscape image for rows: Thumb, else Backdrop, else Primary (an episode's Primary is already a 16:9 still).
    func stillURL(_ item: Item, width: Int) -> URL {
        if item.hasImage("Thumb") { return imageURL(item, "Thumb", width: width) }
        if item.hasBackdrop { return imageURL(item, "Backdrop", width: width) }
        return imageURL(item, "Primary", width: width)
    }

    func streamURL(_ item: Item) -> URL {
        url("/Videos/\(item.id)/stream", ["static": "true", "mediaSourceId": item.id, "ApiKey": credentials?.token ?? ""])
    }

    func trickplayTileURL(_ item: Item, width: Int, index: Int) -> URL {
        url("/Videos/\(item.id)/Trickplay/\(width)/\(index).jpg", ["mediaSourceId": item.id, "ApiKey": credentials?.token ?? ""])
    }

    func report(_ event: PlaybackEvent, item: Item, sessionId: String, positionTicks: Int64, paused: Bool) async {
        #if DEBUG
        // Screenshot runs open the player: keep the demo library's resume points as they are.
        if DemoAutomation.isRunning { return }
        #endif
        let body: [String: Any] = ["ItemId": item.id, "MediaSourceId": item.id, "PlaySessionId": sessionId,
                                   "PositionTicks": positionTicks, "IsPaused": paused,
                                   "PlayMethod": "DirectPlay", "CanSeek": true]
        _ = try? await send("POST", event.rawValue, body: body)
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}
