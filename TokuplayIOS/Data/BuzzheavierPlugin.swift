import Foundation

/// Port of com.plugin.api.Hr (id "buzzheavier").
/// Does what the site's own Download button does in a browser:
///   1. GET the file page, read `hx-get` of the `.gay-button` element.
///   2. GET https://buzzheavier.com<hx-get> with the HTMX headers.
///   3. The final file URL is in the `Hx-Redirect` response header.
public struct BuzzheavierPlugin: StreamPlugin {
    public let name = "Buzzheavier"
    public let version = "1.0.0"
    static let origin = "https://buzzheavier.com"
    /// AVPlayer container support; anything else (e.g. .mkv) would fail with no explanation.
    static let playableExtensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]

    public init() {}

    public func canHandle(serverName: String, sourceId: String) -> Bool { sourceId.contains("buzzheavier.com") }

    public func extract(sourceURL: String, sourceId: String, referer: String, serverId: String,
                        session: URLSession) async throws -> StreamResult {
        guard let pageURL = URL(string: sourceURL) else { throw URLError(.badURL) }

        let (pageData, _) = try await session.data(from: pageURL)
        let html = String(decoding: pageData, as: UTF8.self)

        guard let hxGet = Self.hxGet(in: html), let requestURL = URL(string: Self.origin + hxGet) else {
            throw URLError(.cannotParseResponse)
        }

        var request = URLRequest(url: requestURL)
        request.setValue(sourceURL, forHTTPHeaderField: "hx-current-url")
        request.setValue("true", forHTTPHeaderField: "hx-request")
        request.setValue(sourceURL, forHTTPHeaderField: "Referer")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let redirect = http.value(forHTTPHeaderField: "Hx-Redirect"),
              let finalURL = URL(string: redirect, relativeTo: URL(string: Self.origin))?.absoluteURL else {
            throw URLError(.cannotParseResponse)
        }

        let ext = Self.fileExtension(fromTitle: Self.title(in: html), fallback: finalURL.pathExtension)
        guard ext.isEmpty || Self.playableExtensions.contains(ext) else { throw URLError(.cannotDecodeContentData) }

        let video = VideoTrack(url: finalURL.absoluteString, quality: "",
                               size: Self.size(in: html) ?? "", extension_: ext,
                               headers: ["Referer": Self.origin + "/"])
        return StreamResult(videos: [video])
    }

    // MARK: - HTML helpers (small regexes instead of a full parser)

    /// `hx-get` attribute of the element whose class list contains `gay-button`.
    static func hxGet(in html: String) -> String? {
        guard let tag = firstMatch(#"<[^>]*gay-button[^>]*>"#, in: html, group: 0) else { return nil }
        return firstMatch(#"hx-get\s*=\s*["']([^"']+)["']"#, in: tag, group: 1)?
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func title(in html: String) -> String {
        firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html, group: 1, options: [.dotMatchesLineSeparators])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// "Size - 123.4MB"
    static func size(in html: String) -> String? {
        firstMatch(#"Size\s-\s([\d.]+[KMGT]?B)"#, in: html, group: 1)
    }

    /// Extension from the page title (the title is the file name), else from the final URL path.
    static func fileExtension(fromTitle title: String, fallback: String) -> String {
        if let dot = title.lastIndex(of: ".") {
            let tail = title[title.index(after: dot)...].prefix { $0.isLetter || $0.isNumber }
            if !tail.isEmpty { return tail.lowercased() }
        }
        return fallback.lowercased()
    }

    private static func firstMatch(_ pattern: String, in s: String, group: Int,
                                   options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options.union(.caseInsensitive)),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }
}
