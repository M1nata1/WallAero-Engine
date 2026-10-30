import Foundation

/// The Workshop of Wallpaper Engine as anyone can read it, without signing in: the pages Steam
/// shows in a browser say which items there are, and its public API says what they are. Only
/// getting an item's files takes an account: see `SteamCMD`.
public enum SteamWorkshop {
    public static let appID = "431960"

    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let previewURL: URL?
        /// Size of its files, in bytes.
        public let fileSize: Int64
        public let tags: [String]

        /// The page of the item on Steam.
        public var pageURL: URL {
            URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")!
        }

        /// What it is, as the Workshop's own tag names it.
        public var kindTag: String? {
            tags.first(where: Kind.tags.contains)
        }
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

    public struct Query: Equatable, Sendable {
        public var search = ""
        public var sort = Sort.popular
        public var kind = Kind.all
        /// Whether wallpapers rated for grown-ups are shown too. Steam shows them to anyone.
        public var includesMature = false
        public var page = 1

        public init() {}
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
        let tags = [query.kind.tag, query.includesMature ? nil : "Everyone"].compactMap { $0 }
        components.queryItems! += tags.map { URLQueryItem(name: "requiredtags[]", value: $0) }
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
            guard !tags.contains("Application"), query.includesMature || tags.contains("Everyone") else { return nil }
            let size = (detail["file_size"] as? Int64) ?? Int64(detail["file_size"] as? String ?? "") ?? 0
            // Twice the size of a tile, as Steam scales them for its own pages.
            let preview = (detail["preview_url"] as? String).flatMap { URL(string: $0 + "?imw=432&imh=270&ima=fit&impolicy=Letterbox&letterbox=false") }
            return Item(id: id, title: title, previewURL: preview, fileSize: size, tags: tags)
        }
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
