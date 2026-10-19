import Foundation

// Blogger JSON feed (alt=json). Text nodes are encoded as {"$t": "..."}.
struct BloggerPage: Decodable { let feed: BloggerFeed }

struct BloggerFeed: Decodable {
    let entry: [BloggerEntry]?
    let totalResults: BloggerText?
    enum CodingKeys: String, CodingKey {
        case entry
        case totalResults = "openSearch$totalResults"
    }
}

struct BloggerText: Decodable {
    let value: String?
    enum CodingKeys: String, CodingKey { case value = "$t" }
}

struct BloggerEntry: Decodable {
    struct Link: Decodable { let rel: String?; let href: String? }
    struct Category: Decodable { let term: String? }
    struct Thumb: Decodable { let url: String? }

    let id: BloggerText?
    let title: BloggerText?
    let content: BloggerText?
    let published: BloggerText?
    let link: [Link]?
    let category: [Category]?
    let thumbnail: Thumb?

    enum CodingKeys: String, CodingKey {
        case id, title, content, published, link, category
        case thumbnail = "media$thumbnail"
    }
}

/// JSON stored in the post body of the content blog.
struct PostBody: Decodable {
    struct Source: Decodable { let quality: String?; let key: String? }
    /// `subs` = comma separated Opener-encrypted subtitle URLs.
    struct Server: Decodable { let id: String?; let sources: [Source]?; let subs: String? }
    struct Ep: Decodable { let title: String?; let servers: [Server]? }
    struct InfoList: Decodable { let fansub: String? }
    let title: String?
    let thumb: String?
    let poster: String?
    let aired: String?
    let description: String?
    let info: String?
    let rating: String?
    let infoList: InfoList?
    let episodeList: [Ep]?
    /// Movies have no episodeList; their servers sit at the top level.
    let servers: [Server]?
}

enum APIError: LocalizedError {
    case invalidURL, badResponse(Int), decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL tidak valid"
        case .badResponse(let code): return "Server membalas HTTP \(code)"
        case .decoding: return "Format data tidak dikenali"
        }
    }
}

struct ApiService {
    static let pageSize = 150

    let baseURL: URL
    var session: URLSession = .shared

    /// One page of posts. `query` maps to the feed's `?q=` search.
    func fetchPage(startIndex: Int = 1, query: String? = nil) async throws -> (items: [Content], total: Int) {
        guard var c = URLComponents(url: baseURL.appendingPathComponent("feeds/posts/default"),
                                    resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        var items = [URLQueryItem(name: "start-index", value: "\(startIndex)"),
                     URLQueryItem(name: "max-results", value: "\(Self.pageSize)"),
                     URLQueryItem(name: "alt", value: "json")]
        if let q = query, !q.isEmpty { items.insert(URLQueryItem(name: "q", value: q), at: 0) }
        c.queryItems = items
        guard let url = c.url else { throw APIError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badResponse(http.statusCode) }
        do {
            let feed = try JSONDecoder().decode(BloggerPage.self, from: data).feed
            return ((feed.entry ?? []).compactMap(Self.map), Int(feed.totalResults?.value ?? "") ?? 0)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Follows start-index until every post is loaded (the APK pages 150 at a time).
    func fetchAll(query: String? = nil) async throws -> [Content] {
        var all: [Content] = []
        var start = 1
        while true {
            let page = try await fetchPage(startIndex: start, query: query)
            all += page.items
            start += Self.pageSize
            if page.items.isEmpty || start > page.total { break }
        }
        return all
    }

    // MARK: - Mapping

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func map(_ entry: BloggerEntry) -> Content? {
        guard let id = entry.id?.value, let title = entry.title?.value else { return nil }
        let html = entry.content?.value ?? ""
        if let post = try? JSONDecoder().decode(PostBody.self, from: Data(html.utf8)) {
            return mapPost(post, id: id, title: title, entry: entry)
        }
        let thumb = entry.thumbnail?.url ?? firstMatch(#"<img[^>]+src=["']([^"']+)["']"#, in: html)
        let page = entry.link?.first { $0.rel == "alternate" }?.href
        let summary = plainText(html)
        return Content(
            id: id,
            title: title,
            summary: summary.isEmpty ? nil : summary,
            imageURL: thumb.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) },
            published: entry.published?.value.flatMap { dateFormatter.date(from: $0) },
            labels: entry.category?.compactMap { $0.term } ?? [],
            pageURL: page.flatMap { URL(string: $0) },
            episodes: parseEpisodes(html)
        )
    }

    /// Posts of the Tokuplay content blog carry a JSON body (see `PostBody`); source keys are Opener-encrypted.
    private static func mapPost(_ post: PostBody, id: String, title: String, entry: BloggerEntry) -> Content {
        var episodes = (post.episodeList ?? []).enumerated().map { i, ep in
            Episode(id: "\(id)#\(i)", title: ep.title ?? "Episode \(i + 1)", servers: mapServers(ep.servers))
        }
        if episodes.isEmpty, let servers = post.servers, !servers.isEmpty {
            episodes = [Episode(id: "\(id)#movie", title: "Film", servers: mapServers(servers))]
        }
        let image = (post.poster ?? post.thumb).flatMap { URL(string: $0) }
        let aired = post.aired.flatMap { ISO8601DateFormatter().date(from: $0) }
        return Content(
            id: id,
            title: post.title ?? title,
            summary: post.description,
            imageURL: image,
            published: aired ?? entry.published?.value.flatMap { dateFormatter.date(from: $0) },
            labels: entry.category?.compactMap { $0.term } ?? [],
            pageURL: entry.link?.first { $0.rel == "alternate" }?.href.flatMap { URL(string: $0) },
            episodes: episodes,
            rating: post.rating,
            info: post.info,
            fansub: post.infoList?.fansub
        )
    }

    private static func mapServers(_ servers: [PostBody.Server]?) -> [Server] {
        (servers ?? []).map { s in
            Server(id: s.id ?? "0",
                   name: "Server \(s.id ?? "0")",
                   sources: (s.sources ?? []).compactMap { src in
                       src.key.flatMap { Opener.decrypt($0) }.map { Source(id: $0) }
                   },
                   subtitles: (s.subs ?? "").split(separator: ",").compactMap { Opener.decrypt(String($0)) },
                   referer: "")
        }
    }

    /// Best effort: every `<a href="http...">title</a>` in the post body becomes an episode with one direct
    /// source. The original app resolves hosts through a downloaded plugin that is not part of this port.
    static func parseEpisodes(_ html: String) -> [Episode] {
        guard let re = try? NSRegularExpression(pattern: #"<a[^>]+href=["'](https?://[^"']+)["'][^>]*>(.*?)</a>"#,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.enumerated().map { i, m in
            let href = ns.substring(with: m.range(at: 1))
            let label = plainText(ns.substring(with: m.range(at: 2)))
            return Episode(id: href,
                           title: label.isEmpty ? "Episode \(i + 1)" : label,
                           servers: [Server(id: "0", name: "Direct", sources: [Source(id: href)],
                                            subtitles: [], referer: "")])
        }
    }

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
