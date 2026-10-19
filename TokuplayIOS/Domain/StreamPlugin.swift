import Foundation

// MARK: - Exact port of com.androidku.tokuplay.library.model.*

/// Port of com.androidku.tokuplay.library.model.Video
public struct VideoTrack: Identifiable, Codable, Hashable {
    public let id: String
    public let url: String           // raw string — APK stores as String, not URL
    public let quality: String
    public let mimeType: String
    public let size: String
    public let extension_: String    // "extension" is a reserved word in Swift
    public let headers: [String: String]
    // segments (LongRange → String) omitted; AVPlayer handles segmented HLS natively

    public var resolvedURL: URL? { URL(string: url) }

    public func withQuality(_ q: String) -> VideoTrack {
        VideoTrack(id: id, url: url, quality: q, mimeType: mimeType, size: size, extension_: extension_, headers: headers)
    }

    public init(
        id: String = UUID().uuidString,
        url: String,
        quality: String = "",
        mimeType: String = "",
        size: String = "",
        extension_: String = "",
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.url = url
        self.quality = quality
        self.mimeType = mimeType
        self.size = size
        self.extension_ = extension_
        self.headers = headers
    }
}

/// Port of com.androidku.tokuplay.library.model.Audio
public struct AudioTrack: Identifiable, Codable, Hashable {
    public let id: String
    public let url: String
    public let language: String
    public let mimeType: String
    public let quality: String
    public let headers: [String: String]

    public var resolvedURL: URL? { URL(string: url) }

    public init(
        id: String = UUID().uuidString,
        url: String,
        language: String = "",
        mimeType: String = "",
        quality: String = "",
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.url = url
        self.language = language
        self.mimeType = mimeType
        self.quality = quality
        self.headers = headers
    }
}

/// Port of com.androidku.tokuplay.library.model.Subtitle
/// mimeType values from APK:
///   .srt → "application/x-subrip"
///   .vtt → "text/x-mp4-vtt"
///   .ass → "text/x-ssa"
public struct SubtitleTrack: Identifiable, Codable, Hashable {
    public let id: String
    public let url: String
    public let language: String   // extracted from filename via regex [^/]+\.([A-Za-z0-9]+)\.(srt|vtt|ass)
    public let mimeType: String

    public var resolvedURL: URL? { URL(string: url) }

    public init(
        id: String = UUID().uuidString,
        url: String,
        language: String = "",
        mimeType: String = "application/x-subrip"
    ) {
        self.id = id
        self.url = url
        self.language = language
        self.mimeType = mimeType
    }

    /// Derive mimeType from file extension, matching APK logic exactly.
    public static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "ass": return "text/x-ssa"
        case "vtt": return "text/x-mp4-vtt"
        default:    return "application/x-subrip"
        }
    }

    /// Extract subtitle language from URL path, matching APK regex:
    /// [^/]+\.([A-Za-z0-9]+)\.(srt|vtt|ass)
    public static func language(fromURL urlString: String) -> String {
        let pattern = "[^/]+\\.([A-Za-z0-9]+)\\.(srt|vtt|ass)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: urlString,
                range: NSRange(urlString.startIndex..., in: urlString)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: urlString)
        else { return "" }
        return String(urlString[range]).lowercased()
    }
}

/// Port of com.androidku.tokuplay.library.model.Stream
/// drm / drmLicense map to FairPlay on iOS.
public struct StreamResult: Codable, Hashable {
    public var videos: [VideoTrack]
    public var audios: [AudioTrack]
    public var subtitles: [SubtitleTrack]
    public var drm: String?
    public var drmLicense: String?
    public var errorCode: String?

    public var hasDRM: Bool { drm != nil && !(drm?.isEmpty ?? true) }

    public init(
        videos: [VideoTrack] = [],
        audios: [AudioTrack] = [],
        subtitles: [SubtitleTrack] = [],
        drm: String? = nil,
        drmLicense: String? = nil,
        errorCode: String? = nil
    ) {
        self.videos = videos
        self.audios = audios
        self.subtitles = subtitles
        self.drm = drm
        self.drmLicense = drmLicense
        self.errorCode = errorCode
    }
}

/// Port of com.androidku.tokuplay.domain.model.Source
/// Fields: a (url), b (name/id), c (referer)
public struct Source: Identifiable, Codable, Hashable {
    public let id: String     // field a — source URL or identifier
    public let name: String   // field b — source name / loader key
    public let referer: String // field c — referer header value
    /// Quality label from the content blog ("480p", "720p", ...). Optional so old saved data still decodes.
    public var quality: String?

    public init(id: String, name: String = "", referer: String = "", quality: String? = nil) {
        self.id = id
        self.name = name
        self.referer = referer
        self.quality = quality
    }
}

/// Plugin interface — port of com.androidku.tokuplay.library.plugin.BasePlugin
public protocol StreamPlugin {
    var name: String { get }
    var version: String { get }

    /// Port of BasePlugin.name(String, String): boolean
    func canHandle(serverName: String, sourceId: String) -> Bool

    /// Port of LoaderAPI.get(...)
    func extract(
        sourceURL: String,
        sourceId: String,
        referer: String,
        serverId: String,
        session: URLSession
    ) async throws -> StreamResult
}
