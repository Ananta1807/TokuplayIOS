import Foundation

// Home layout published by the content blog at /p/db.html (JSON inside `.post-body`).

struct HomeGroup: Decodable, Identifiable {
    let id = UUID()
    let type: String?
    let title: String?
    let enable: String?
    let target: String?
    let labels: [String]?
    let picks: [String]?
    let limit: String?
    let description: String?

    enum CodingKeys: String, CodingKey { case type, title, enable, target, labels, picks, limit, description }

    var isEnabled: Bool { enable != "0" }
    /// "0" or missing means no limit.
    var maxItems: Int? { Int(limit ?? "").flatMap { $0 > 0 ? $0 : nil } }
}

struct HomeTab: Decodable, Identifiable {
    let id = UUID()
    let title: String
    let groups: [HomeGroup]

    enum CodingKeys: String, CodingKey { case title, groups }
}

struct SiteConfig {
    var tabs: [HomeTab]
    /// Post ids listed in the page's `.popular` element, most popular first.
    var popularIDs: [String]
}

enum ConfigService {
    private struct Root: Decodable { let cat: [HomeTab]? }

    static func fetch(baseURL: URL, session: URLSession = .shared) async throws -> SiteConfig {
        let url = baseURL.appendingPathComponent("p/db.html")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let html = String(decoding: data, as: UTF8.self)
        guard let body = firstGroup(#"class=['"]post-body[^'"]*['"][^>]*>(.*?)</div>"#, in: html) else {
            throw APIError.decoding(URLError(.cannotParseResponse))
        }
        let json = ApiService.plainText(body)
        let root: Root
        do { root = try JSONDecoder().decode(Root.self, from: Data(json.utf8)) } catch { throw APIError.decoding(error) }

        var popular: [String] = []
        if let block = firstGroup(#"class=['"]popular['"][^>]*>(.*?)</div>"#, in: html),
           let re = try? NSRegularExpression(pattern: #"<span[^>]*>\s*(\d+)\s*</span>"#) {
            let ns = block as NSString
            popular = re.matches(in: block, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        }
        return SiteConfig(tabs: root.cat ?? [], popularIDs: popular)
    }

    private static func firstGroup(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
