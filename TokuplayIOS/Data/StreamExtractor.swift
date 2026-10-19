import Foundation

// MARK: - Exact port of StreamRepository.a (decompiled smali logic)

public class StreamRepository: ObservableObject {
    @Published public private(set) var streamResult: StreamResult?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?

    private var registeredPlugins: [StreamPlugin] = []
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
        registerDefaultPlugins()
    }

    public func register(plugin: StreamPlugin) {
        registeredPlugins.append(plugin)
    }

    private func registerDefaultPlugins() {
        // First-party loaders go first; DirectStreamPlugin handles plain http(s) URLs.
        register(plugin: StoragePlugin())
        register(plugin: DashPlugin())
        register(plugin: Mp4PathPlugin())
        register(plugin: BuzzheavierPlugin())
        register(plugin: DirectStreamPlugin())
    }

    /// Port of StreamRepository.a(StreamRepository, Context, Server, Continuation)
    ///
    /// The APK method runs the following algorithm:
    /// 1. Iterates over Server.sources (List<Source>)
    /// 2. For each Source:
    ///    a. Checks if APIHolder.loaderApis has a loader matching source.b (or decoded via Opener.a)
    ///    b. If matched, calls loader.get(source.b, source.a, source.c, server.g, callbacks...)
    ///    c. If not matched, constructs a Video directly:
    ///       - url = source.b
    ///       - quality = substring after last '.' of source.b (extension as quality)
    ///       - headers = ["referer": server.g] if server.g != null
    ///       - adds to video list
    /// 3. If video list is empty -> returns Stream(errorCode = String(server.id))
    /// 4. Sorts videos by quality descending (via StreamRepository$extract$$inlined$sortedByDescending$1)
    /// 5. Iterates over server.subtitles (List<String>):
    ///    - regex: [^/]+\.([A-Za-z0-9]+)\.(srt|vtt|ass)
    ///    - lang = group 1 lowercased
    ///    - mime = "text/x-ssa" for .ass, "text/x-mp4-vtt" for .vtt, "application/x-subrip" for .srt
    ///    - adds Subtitle(url, lang, mime) to subtitle list
    /// 6. Returns Stream(videos, audios, subtitles)
    public func extract(
        sources: [Source],
        serverName: String = "",
        serverId: String = "",
        serverReferer: String = "",
        subtitleURLs: [String] = []
    ) async -> StreamResult {
        await MainActor.run {
            self.isLoading = true
            self.error = nil
            self.streamResult = nil
        }
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        var collectedVideos: [VideoTrack] = []
        var collectedAudios: [AudioTrack] = []
        var collectedSubtitles: [SubtitleTrack] = []

        // Step 1 & 2: Process each source
        for source in sources {
            var handledByPlugin = false

            for plugin in registeredPlugins {
                if plugin.canHandle(serverName: serverName, sourceId: source.id) {
                    do {
                        let result = try await plugin.extract(
                            sourceURL: source.name.isEmpty ? source.id : source.name,
                            sourceId: source.id,
                            referer: source.referer,
                            serverId: serverId,
                            session: session
                        )
                        // The blog knows the quality of each source; loaders usually do not.
                        let label = source.quality ?? ""
                        collectedVideos.append(contentsOf: result.videos.map {
                            $0.quality.isEmpty && !label.isEmpty ? $0.withQuality(label) : $0
                        })
                        collectedAudios.append(contentsOf: result.audios)
                        collectedSubtitles.append(contentsOf: result.subtitles)
                        handledByPlugin = true
                        break
                    } catch {
                        // Plugin failed; fall through to direct video construction
                        continue
                    }
                }
            }

            // Step 2.c: Fallback matching APK decompilation
            // If no plugin handled it, construct direct VideoTrack
            if !handledByPlugin {
                let rawURL = source.name.isEmpty ? source.id : source.name
                // Not in the APK: skip hosts this port cannot resolve instead of handing a web page to AVPlayer.
                guard StreamSupport.isDirectMedia(rawURL) else { continue }

                // APK: find last '.', substring(idx + 1) -> quality/extension
                let ext: String
                if let lastDot = rawURL.lastIndex(of: ".") {
                    let nextIdx = rawURL.index(after: lastDot)
                    ext = String(rawURL[nextIdx...])
                } else {
                    ext = ""
                }

                // APK: if server.g (referer) != null, headers["referer"] = server.g
                var headers: [String: String] = [:]
                if !serverReferer.isEmpty {
                    headers["referer"] = serverReferer
                }

                let fallbackVideo = VideoTrack(
                    url: rawURL,
                    quality: (source.quality ?? "").isEmpty ? ext : source.quality!,
                    headers: headers
                )
                collectedVideos.append(fallbackVideo)
            }
        }

        // Step 3: If video list is empty, return error with serverId
        if collectedVideos.isEmpty {
            let emptyResult = StreamResult(errorCode: serverId)
            await MainActor.run {
                self.streamResult = emptyResult
                self.error = "No videos available (error code \(serverId))"
            }
            return emptyResult
        }

        // Step 4: Sort videos by quality descending (matching APK comparator)
        let sortedVideos = collectedVideos.sorted { v1, v2 in
            let q1 = extractQualityNumber(from: v1.quality)
            let q2 = extractQualityNumber(from: v2.quality)
            return q1 > q2
        }

        // Step 5: Process subtitles (matching APK regex and mime assignment)
        for subURL in subtitleURLs {
            let lang = SubtitleTrack.language(fromURL: subURL)
            let ext = (subURL as NSString).pathExtension
            let mime = SubtitleTrack.mimeType(for: ext)
            collectedSubtitles.append(
                SubtitleTrack(url: subURL, language: lang, mimeType: mime)
            )
        }

        // Step 6: Return complete StreamResult
        let finalResult = StreamResult(
            videos: sortedVideos,
            audios: collectedAudios,
            subtitles: collectedSubtitles
        )

        await MainActor.run {
            self.streamResult = finalResult
        }

        return finalResult
    }

    /// Helper to sort quality strings like "1080p", "720p", "480p" descending
    private func extractQualityNumber(from quality: String) -> Int {
        let digits = quality.filter { $0.isNumber }
        return Int(digits) ?? 0
    }
}

// MARK: - Direct / Fallback Plugin

public struct DirectStreamPlugin: StreamPlugin {
    public let name = "DirectStream"
    public let version = "1.0.0"

    public func canHandle(serverName: String, sourceId: String) -> Bool {
        // Handles direct media URLs (.m3u8, .mp4, etc.)
        StreamSupport.isDirectMedia(sourceId)
    }

    public func extract(
        sourceURL: String,
        sourceId: String,
        referer: String,
        serverId: String,
        session: URLSession
    ) async throws -> StreamResult {
        var headers: [String: String] = [:]
        if !referer.isEmpty {
            headers["referer"] = referer
        }

        let ext = (sourceURL as NSString).pathExtension
        let video = VideoTrack(
            url: sourceURL,
            quality: ext.isEmpty ? "Auto" : ext,
            headers: headers
        )
        return StreamResult(videos: [video])
    }
}
