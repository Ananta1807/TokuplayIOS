import Foundation
import CommonCrypto
import CryptoKit

// Ports of the two first-party loaders from the Tokuplay runtime plugin:
//   com.plugin.api.Ct  (id "@storage") -> https://blob.tokuplay.xyz/f/...
//   com.plugin.api.Mp  (id "mpd:")     -> https://dash.tokuplay.xyz/{stream,video}/...
// Format derived from static analysis of the shipped plugin (data.15.uuid).

// MARK: - What this port can actually play

enum StreamSupport {
    static let mediaExtensions: Set<String> = ["m3u8", "mp4", "m4v", "mov"]

    /// Plain http(s) link that points straight at a media file AVPlayer understands.
    static func isDirectMedia(_ id: String) -> Bool {
        guard let url = URL(string: id), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return mediaExtensions.contains(url.pathExtension.lowercased())
    }

    /// Real data uses `@storage:...` and `@mpd:<id>`; the plugin matches loaders by substring, so match the same way.
    /// `mpd:<id>` without `@` resolves to a DASH manifest, which AVPlayer cannot play.
    static func isPlayable(_ id: String) -> Bool {
        id.contains("@storage") || id.contains("@mp4") || (id.contains("mpd:") && id.contains("@")) || isDirectMedia(id)
    }

    /// Host name of a source that only exists on a third-party site (e.g. a file-host page), if any.
    static func unsupportedHost(_ id: String) -> String? {
        guard !isPlayable(id), let url = URL(string: id), url.scheme?.hasPrefix("http") == true else { return nil }
        return url.host?.replacingOccurrences(of: "www.", with: "")
    }

    static func isPlayable(_ episode: Episode) -> Bool {
        episode.servers.contains { $0.sources.contains { isPlayable($0.id) } }
    }

    /// Why an episode cannot be played, or nil if it can.
    static func explanation(for episode: Episode) -> String? {
        if isPlayable(episode) { return nil }
        let hosts = Set(episode.servers.flatMap { $0.sources.compactMap { unsupportedHost($0.id) } }).sorted()
        if episode.servers.allSatisfy({ $0.sources.isEmpty }) { return "Episode ini belum punya sumber video." }
        if hosts.isEmpty { return "Format sumber video episode ini belum didukung di versi iOS." }
        return "Episode ini hanya tersedia di \(hosts.joined(separator: ", ")), yang belum didukung di versi iOS."
    }
}

// MARK: - Path token (com.plugin.utils.AesHelper.secure)

enum PathToken {
    /// AES-256-CBC/PKCS7, key = SHA-256(password), IV = 16 zero bytes,
    /// output = base64 URL-safe, no padding, no wrapping (Android flags 11).
    static func encrypt(_ text: String, password: String = "context") -> String? {
        let key = Array(SHA256.hash(data: Data(password.utf8)))
        let input = Array(text.utf8)
        let iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        var out = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, input, input.count, &out, out.count, &written)
        guard status == kCCSuccess else { return nil }
        return Data(out.prefix(written)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Kotlin-style string helpers (missing delimiter returns the whole string)

private extension String {
    func after(_ d: String) -> String { range(of: d).map { String(self[$0.upperBound...]) } ?? self }
    func before(_ d: String) -> String { range(of: d).map { String(self[..<$0.lowerBound]) } ?? self }
    func afterLast(_ d: String) -> String { range(of: d, options: .backwards).map { String(self[$0.upperBound...]) } ?? self }
    func beforeLast(_ d: String) -> String { range(of: d, options: .backwards).map { String(self[..<$0.lowerBound]) } ?? self }
}

// MARK: - @storage  (blob.tokuplay.xyz)

/// Source string: `@storage:<a-b-c-file>[|<res>,<res>][?<lang>,<lang>]`
/// The id is split on its last "-": the head becomes the folder path ("-" -> "/", then encrypted),
/// the tail the file name.
public struct StoragePlugin: StreamPlugin {
    public let name = "TokuplayStorage"
    public let version = "1.0.0"
    static let base = "https://blob.tokuplay.xyz/f/"

    public init() {}

    public func canHandle(serverName: String, sourceId: String) -> Bool { sourceId.contains("@storage") }

    public func extract(sourceURL: String, sourceId: String, referer: String, serverId: String,
                        session: URLSession) async throws -> StreamResult {
        let url = sourceURL
        let hasMulti = url.contains("|")
        let hasSub = url.contains("?")
        let headers = ["Referer": "https://tokuplay.xyz/"]

        func locate(_ id: String) throws -> (secure: String, file: String) {
            let path = id.beforeLast("-").replacingOccurrences(of: "-", with: "/")
            guard let secure = PathToken.encrypt(path) else { throw URLError(.cannotDecodeContentData) }
            return (secure, id.afterLast("-"))
        }

        var subtitles: [SubtitleTrack] = []
        if hasSub {
            let langs = url.after("?").split(separator: ",").map(String.init)
            var id = url.after(":")
            if hasMulti {
                id = id.before("|")
            } else {
                id = id.before("?")
                for s in [".mp4", ".mkv", ".360p", ".480p", ".720p", ".1080p", "-master.m3u8"] {
                    id = id.replacingOccurrences(of: s, with: "")
                }
            }
            let (secure, file) = try locate(id)
            subtitles = langs.map {
                SubtitleTrack(url: "\(Self.base)\(secure)/\(file).\($0).srt", language: $0, mimeType: "application/x-subrip")
            }
        }

        let videos: [VideoTrack]
        if hasMulti {
            let (secure, file) = try locate(url.after(":").before("|"))
            var resPart = url.after("|")
            if hasSub { resPart = resPart.before("?") }
            let resolutions = resPart.split(separator: ",").map(String.init)
            videos = resolutions.map {
                VideoTrack(url: "\(Self.base)\(secure)/\(file).\($0).mp4", quality: $0, extension_: "mp4", headers: headers)
            }
        } else {
            let id = hasSub ? url.after(":").before("?") : url.after(":")
            let (secure, file) = try locate(id)
            videos = [VideoTrack(url: "\(Self.base)\(secure)/\(file)", quality: "", headers: headers)]
        }
        return StreamResult(videos: videos, subtitles: subtitles)
    }
}

// MARK: - @mp4  (seedbox, plain http)

/// Source string: `@mp4:<a-b-c-file.720p.mp4>` -> `http://skathi.whatbox.ca:26322/a/b/c/file.720p.mp4`
/// (every "-" in the id becomes "/"; `|res,res` expands to `<id>.<res>.mp4`).
/// Port of com.plugin.api.Cd without its "cdn" variant. The host is not under tokuplay.xyz:
/// confirm you control it, otherwise remove this plugin from `registerDefaultPlugins`.
public struct Mp4PathPlugin: StreamPlugin {
    public let name = "TokuplayMp4"
    public let version = "1.0.0"
    static let base = "http://skathi.whatbox.ca:26322"

    public init() {}

    public func canHandle(serverName: String, sourceId: String) -> Bool { sourceId.contains("@mp4") }

    public func extract(sourceURL: String, sourceId: String, referer: String, serverId: String,
                        session: URLSession) async throws -> StreamResult {
        let id = sourceURL.after(":").before("|")
        let vid = id.replacingOccurrences(of: "-", with: "/")
        if sourceURL.contains("|") {
            let videos = sourceURL.after("|").split(separator: ",").map {
                VideoTrack(url: "\(Self.base)/\(vid).\($0).mp4", quality: String($0), extension_: "mp4")
            }
            return StreamResult(videos: videos)
        }
        return StreamResult(videos: [VideoTrack(url: "\(Self.base)/\(vid)", extension_: "mp4")])
    }
}

// MARK: - mpd:  (dash.tokuplay.xyz)

/// Source string: `mpd:<id>` -> `https://dash.tokuplay.xyz/video/<id>.mpd`
///                `mpd:<id>@...` -> GET `https://dash.tokuplay.xyz/stream/<id>` returning `{ "url": "..." }`.
/// Note: AVPlayer cannot play DASH (.mpd); only the `@` form is playable if the returned url is HLS/MP4.
public struct DashPlugin: StreamPlugin {
    public let name = "TokuplayDash"
    public let version = "1.0.0"
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"

    public init() {}

    public func canHandle(serverName: String, sourceId: String) -> Bool { sourceId.contains("mpd:") }

    public func extract(sourceURL: String, sourceId: String, referer: String, serverId: String,
                        session: URLSession) async throws -> StreamResult {
        let id = sourceURL.after(":")
        if sourceURL.contains("@") {
            guard let api = URL(string: "https://dash.tokuplay.xyz/stream/\(id)") else { throw URLError(.badURL) }
            var req = URLRequest(url: api)
            req.setValue("https://tokuplay.xyz/", forHTTPHeaderField: "Referer")
            let (data, _) = try await session.data(for: req)
            guard !data.isEmpty,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let link = json["url"] as? String else { throw URLError(.cannotParseResponse) }
            return StreamResult(videos: [VideoTrack(url: link, headers: ["User-Agent": Self.userAgent])])
        }
        let video = VideoTrack(url: "https://dash.tokuplay.xyz/video/\(id).mpd", extension_: "mpd",
                               headers: ["User-Agent": Self.userAgent, "Origin": "https://youtube.googleapis.com"])
        return StreamResult(videos: [video])
    }
}
