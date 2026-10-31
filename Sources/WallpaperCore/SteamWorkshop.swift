import Foundation

/// The Workshop of Wallpaper Engine as anyone can read it, without signing in: the pages Steam
/// shows in a browser say which items there are, and its public API says what they are. Only
/// getting an item's files takes an account: see `SteamCMD`.
public enum SteamWorkshop {
    public static let appID = "431960"
    public static let animeTag = "Anime"

    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let previewURL: URL?
        /// The preview as its author made it: moving, when it is a GIF. Those are small squares
        /// of a megabyte, which Steam does not scale.
        public let originalPreviewURL: URL?
        /// Size of its files, in bytes.
        public let fileSize: Int64
        public let tags: [String]
        /// What the author says about it, as plain text.
        public let description: String
        public let subscriptions: Int
        public let favorites: Int
        public let updated: Date?

        /// The page of the item on Steam.
        public var pageURL: URL {
            URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")!
        }

        /// What it is, as the Workshop's own tag names it.
        public var kindTag: String? {
            tags.first(where: Kind.tags.contains)
        }
    }

    /// What only the item's page on Steam says.
    public struct Page: Equatable, Sendable {
        public let author: String?
        /// From one to five; nothing until enough people have voted.
        public let stars: Int?
    }

    public enum Sort: String, CaseIterable, Sendable {
        /// What is being subscribed to this week.
        case popular
        case recent
        case subscribed

        fileprivate var parameters: [String: String] {
            switch self {
            case .popular: ["browsesort": "trend", "days": "7"]
            case .recent: ["browsesort": "mostrecent"]
            case .subscribed: ["browsesort": "totaluniquesubscribers"]
            }
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case all
        case scene
        case video
        case web

        fileprivate var tag: String? {
            switch self {
            case .all: nil
            case .scene: "Scene"
            case .video: "Video"
            case .web: "Web"
            }
        }

        fileprivate static let tags = allCases.compactMap(\.tag)
    }

    /// The tags a wallpaper can be looked for by, as Steam's own pages group them. The type, the
    /// age rating and anime have controls of their own.
    public static let tagCategories: [(name: String, tags: [String])] = [
        ("Genre", ["Abstract", "Animal", "Cartoon", "CGI", "Cyberpunk", "Fantasy", "Game", "Girls", "Guys", "Landscape",
                   "Medieval", "Memes", "MMD", "Music", "Nature", "Pixel art", "Relaxing", "Retro", "Sci-Fi", "Sports",
                   "Technology", "Television", "Vehicle", "Unspecified"]),
        ("Resolution", resolutionTags),
        ("Miscellaneous", ["Approved", "Audio responsive", "3D", "Customizable", "Puppet Warp", "HDR", "Media Integration",
                           "User Shortcut", "Video Texture", "Asset Pack"]),
    ]

    /// An item has one of these, so asking for two would find nothing.
    private static let resolutionTags = [
        "Standard Definition", "1280 x 720", "1366 x 768", "1920 x 1080", "2560 x 1440", "3840 x 2160",
        "Ultrawide Standard Definition", "Ultrawide 2560 x 1080", "Ultrawide 3440 x 1440",
        "Dual Standard Definition", "Dual 3840 x 1080", "Dual 5120 x 1440", "Dual 7680 x 2160",
        "Triple Standard Definition", "Triple 4096 x 768", "Triple 5760 x 1080", "Triple 7680 x 1440", "Triple 11520 x 2160",
        "Portrait Standard Definition", "Portrait 720 x 1280", "Portrait 1080 x 1920", "Portrait 1440 x 2560", "Portrait 2160 x 3840",
        "Other resolution", "Dynamic resolution",
    ]

    public struct Query: Equatable, Sendable {
        public var search = ""
        public var sort = Sort.popular
        public var kind = Kind.all
        /// What an item has to have, all of it: Steam finds only what has every tag asked for.
        public private(set) var tags: Set<String> = []
        /// Whether wallpapers rated for grown-ups are shown too. Steam shows them to anyone.
        public var includesMature = false
        /// Whether anime is shown. There is a lot of it, and not everyone wants to see it.
        public var includesAnime = true
        public var page = 1

        public init() {}

        /// Takes the tags ticked now. A second resolution takes the place of the first.
        public mutating func setTags(_ new: Set<String>) {
            let resolutions = Set(SteamWorkshop.resolutionTags)
            let added = new.subtracting(tags).intersection(resolutions)
            tags = added.isEmpty ? new : new.subtracting(resolutions).union(added.prefix(1))
        }

        /// Back to what is asked for at first.
        public mutating func resetTags() {
            tags = []
            includesAnime = true
            includesMature = false
        }
    }

    /// The page of a browser's listing for a query. A search goes by relevance, whatever the sort.
    static func listingURL(for query: Query) -> URL {
        var parameters = ["appid": appID, "section": "readytouseitems", "numperpage": "30", "p": String(query.page)]
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty {
            parameters.merge(query.sort.parameters) { $1 }
        } else {
            parameters["browsesort"] = "textsearch"
            parameters["searchtext"] = search
        }
        var components = URLComponents(string: "https://steamcommunity.com/workshop/browse/")!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let tags = [query.kind.tag, query.includesMature ? nil : "Everyone"].compactMap { $0 } + query.tags.sorted()
        components.queryItems! += tags.map { URLQueryItem(name: "requiredtags[]", value: $0) }
        if !query.includesAnime {
            components.queryItems!.append(URLQueryItem(name: "excludedtags[]", value: animeTag))
        }
        return components.url!
    }

    /// The numbers of the items a listing links to, in its order.
    static func itemIDs(inListing page: String) -> [String] {
        var seen: Set<String> = []
        let marker = "filedetails/?id="
        var ids: [String] = []
        var rest = page[...]
        while let found = rest.range(of: marker) {
            let id = rest[found.upperBound...].prefix(while: \.isNumber)
            if !id.isEmpty, seen.insert(String(id)).inserted {
                ids.append(String(id))
            }
            rest = rest[found.upperBound...]
        }
        return ids
    }

    /// The items in an answer of `GetPublishedFileDetails`. Left out is what is not there for
    /// anyone to get, and what the app cannot show: a Windows program made into a wallpaper.
    static func items(inDetails data: Data, query: Query) throws -> [Item] {
        let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let details = (answer?["response"] as? [String: Any])?["publishedfiledetails"] as? [[String: Any]] ?? []
        return details.compactMap { detail in
            guard (detail["result"] as? Int) == 1,
                  (detail["consumer_app_id"] as? Int).map(String.init) == appID,
                  (detail["banned"] as? Int ?? 0) == 0,
                  (detail["visibility"] as? Int ?? 0) == 0,
                  let id = detail["publishedfileid"] as? String,
                  let title = detail["title"] as? String
            else {
                return nil
            }
            let tags = (detail["tags"] as? [[String: Any]] ?? []).compactMap { $0["tag"] as? String }
            // A listing also links to items beside the ones asked for.
            guard !tags.contains("Application"), query.includesMature || tags.contains("Everyone"),
                  query.includesAnime || !tags.contains(animeTag)
            else {
                return nil
            }
            let size = (detail["file_size"] as? Int64) ?? Int64(detail["file_size"] as? String ?? "") ?? 0
            // Twice the size of a tile, as Steam scales them for its own pages.
            let original = detail["preview_url"] as? String
            let preview = original.flatMap { URL(string: $0 + "?imw=432&imh=270&ima=fit&impolicy=Letterbox&letterbox=false") }
            return Item(id: id, title: title, previewURL: preview, originalPreviewURL: original.flatMap(URL.init(string:)),
                        fileSize: size, tags: tags, description: plainText(ofDescription: detail["description"] as? String ?? ""),
                        subscriptions: detail["subscriptions"] as? Int ?? 0, favorites: detail["favorited"] as? Int ?? 0,
                        updated: (detail["time_updated"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) })
        }
    }

    /// A description without Steam's markup. Only its own tags go: a title in brackets stays.
    static func plainText(ofDescription description: String) -> String {
        let tags = "h1|h2|h3|b|i|u|s|strike|spoiler|noparse|hr|url|list|olist|quote|code|table|tr|td|th"
        let rules = [(#"(?is)\[(img|previewyoutube)[^\]]*\].*?\[/\1\]"#, ""),
                     (#"\[\*\]"#, "• "),
                     ("(?i)\\[/?(\(tags))(=[^\\]]*)?\\]", "")]
        let text = rules.reduce(description) {
            $0.replacingOccurrences(of: $1.0, with: $1.1, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the page of an item says beyond the API, as far as it can be made out.
    static func page(inHTML html: String) -> Page {
        var author: String?
        if let block = html.range(of: "class=\"creatorsBlock\""),
           let name = html[block.upperBound...].range(of: "class=\"friendBlockContent\">") {
            let text = html[name.upperBound...].prefix { $0 != "<" }.trimmingCharacters(in: .whitespacesAndNewlines)
            author = text.isEmpty ? nil : text
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        var stars: Int?
        if let rating = html.range(of: "class=\"fileRatingDetails\""),
           let star = html[rating.upperBound...].range(of: "-star_large") {
            stars = html[..<star.lowerBound].last?.wholeNumberValue
        }
        return Page(author: author, stars: stars)
    }

    /// Reads the item's page; asked for only when the user opens the item.
    public static func page(of item: Item) async throws -> Page {
        var request = URLRequest(url: item.pageURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return page(inHTML: String(decoding: data, as: UTF8.self))
    }

    /// One page of what the query finds. Empty past the last page.
    public static func items(for query: Query) async throws -> [Item] {
        var listing = URLRequest(url: listingURL(for: query))
        // Steam answers a program with no name of its own with a page of no use.
        listing.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (page, _) = try await URLSession.shared.data(for: listing)
        let ids = itemIDs(inListing: String(decoding: page, as: UTF8.self))
        guard !ids.isEmpty else { return [] }

        var fields = [("itemcount", String(ids.count))]
        fields += ids.enumerated().map { ("publishedfileids[\($0.offset)]", $0.element) }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.0)=\($0.1)" }
            .joined(separator: "&")
        var details = URLRequest(url: URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!)
        details.httpMethod = "POST"
        details.httpBody = Data(body.utf8)
        details.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: details)
        return try items(inDetails: data, query: query)
    }
}
