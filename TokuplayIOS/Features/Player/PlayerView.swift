import SwiftUI
import AVKit

struct PlayerRequest: Identifiable {
    let id = UUID()
    let title: String
    let stream: StreamResult
    let episode: Episode
    /// Seconds to resume from (0 = from the beginning).
    var startAt: Double = 0
}

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var videos: [VideoTrack] = []
    @Published private(set) var subtitleTracks: [SubtitleTrack] = []
    @Published var selected: VideoTrack?
    @Published var subtitle: SubtitleTrack?
    @Published var subtitleText: String?
    /// True once the current episode played to its end.
    @Published var ended = false

    /// (request, position, duration) every few seconds and when the episode ends.
    var onProgress: (@MainActor (PlayerRequest, Double, Double) -> Void)?

    private let preferredQuality: Int
    private var request: PlayerRequest?
    private var cues: [SubtitleCue] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var pendingStart = 0.0
    private var lastReported = -10.0

    init(preferredQuality: Int) {
        self.preferredQuality = preferredQuality
        Self.activateAudioSession()
        player.isMuted = false
        player.volume = 1
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil,
                                                             queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.report()
                self.ended = true
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    /// Without a playback category iOS uses "ambient", which the silent switch mutes. A video player must use
    /// .playback so sound plays with the ringer off and keeps going in Picture in Picture / background audio.
    private static func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            print("AVAudioSession setup failed: \(error)")
        }
    }

    /// Loads a (new) episode into the same player.
    func load(_ request: PlayerRequest) {
        self.request = request
        Self.activateAudioSession()
        ended = false
        lastReported = -10
        pendingStart = request.startAt
        videos = request.stream.videos.filter { $0.resolvedURL != nil }
        subtitleTracks = request.stream.subtitles.filter { $0.resolvedURL != nil }
        if let track = pick(videos) { select(track, keepPosition: false) }
        selectSubtitle(subtitleTracks.first)
    }

    /// Switches quality; keeps the playback position unless this is the first load of an episode.
    func select(_ track: VideoTrack, keepPosition: Bool = true) {
        guard let url = track.resolvedURL else { return }
        let resume = keepPosition ? player.currentTime() : .invalid
        var options: [String: Any] = [:]
        if !track.headers.isEmpty {
            // Widely used key for per-request headers (e.g. Referer); not exposed as a public constant.
            options["AVURLAssetHTTPHeaderFieldsKey"] = track.headers
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: url, options: options)))
        if resume.isValid && resume.seconds > 0 {
            player.seek(to: resume)
        } else if pendingStart > 0 {
            player.seek(to: CMTime(seconds: pendingStart, preferredTimescale: 600))
            pendingStart = 0
        }
        selected = track
        player.play()
    }

    func selectSubtitle(_ track: SubtitleTrack?) {
        loadTask?.cancel()
        subtitle = track
        subtitleText = nil
        cues = []
        guard let track, let url = track.resolvedURL else { return }
        loadTask = Task { [weak self] in
            var request = URLRequest(url: url)
            // Subtitles live next to the video on blob.tokuplay.xyz, which checks the Referer.
            if url.host?.hasSuffix("tokuplay.xyz") == true { request.setValue("https://tokuplay.xyz/", forHTTPHeaderField: "Referer") }
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            let parsed = SubtitleParser.parse(text, mimeType: track.mimeType)
            guard !Task.isCancelled else { return }
            self?.cues = parsed
        }
    }

    /// Call when the player closes so the last position is saved.
    func report() {
        guard let request else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        onProgress?(request, player.currentTime().seconds, duration.isFinite ? duration : 0)
    }

    // MARK: - Private

    private func tick(_ time: Double) {
        let text = cues.isEmpty ? nil : SubtitleParser.cue(at: time, in: cues)?.text
        if text != subtitleText { subtitleText = text }
        if time.isFinite, abs(time - lastReported) >= 5 {
            lastReported = time
            report()
        }
    }

    private func height(_ q: String) -> Int { Int(q.filter(\.isNumber)) ?? 0 }

    /// Highest quality when `preferredQuality` is 0, else the best one not above it (or the lowest if all are higher).
    private func pick(_ tracks: [VideoTrack]) -> VideoTrack? {
        let sorted = tracks.sorted { height($0.quality) > height($1.quality) }
        guard preferredQuality > 0 else { return sorted.first }
        return sorted.first { height($0.quality) <= preferredQuality } ?? sorted.last
    }
}

struct PlayerView: View {
    let content: Content
    let loadEpisode: @MainActor (Episode) async -> PlayerRequest?

    @StateObject private var model: PlayerModel
    @State private var current: PlayerRequest
    @State private var countdown: Int?
    @State private var isLoadingNext = false
    @Environment(\.dismiss) private var dismiss

    init(content: Content, request: PlayerRequest, preferredQuality: Int,
         loadEpisode: @escaping @MainActor (Episode) async -> PlayerRequest?,
         onProgress: @escaping @MainActor (PlayerRequest, Double, Double) -> Void) {
        self.content = content
        self.loadEpisode = loadEpisode
        _current = State(initialValue: request)
        // Built inside the autoclosure so it runs once; a model created eagerly here would start
        // playing (and be thrown away) every time the parent view re-evaluates.
        _model = StateObject(wrappedValue: {
            let m = PlayerModel(preferredQuality: preferredQuality)
            m.onProgress = onProgress
            m.load(request)
            return m
        }())
    }

    /// Next episode after the current one that this app can play.
    private var nextEpisode: Episode? {
        guard let i = content.episodes.firstIndex(where: { $0.id == current.episode.id }) else { return nil }
        return content.episodes.dropFirst(i + 1).first { StreamSupport.isPlayable($0) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: model.player).ignoresSafeArea()

            if let text = model.subtitleText {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 56)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            topBar

            if model.ended, let next = nextEpisode {
                nextCard(next).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        // Counts down after an episode ends, then starts the next one. Setting `ended = false` cancels it.
        .task(id: model.ended) {
            guard model.ended, nextEpisode != nil else { return }
            for s in stride(from: 5, through: 1, by: -1) {
                countdown = s
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { countdown = nil; return }
            }
            countdown = nil
            await playNext()
        }
        .onDisappear {
            model.report()
            model.player.pause()
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
            Text(current.title).font(.subheadline).lineLimit(1)
            Spacer()
            if !model.subtitleTracks.isEmpty {
                Menu {
                    Button("Mati") { model.selectSubtitle(nil) }
                    ForEach(model.subtitleTracks) { track in
                        Button(track.language.isEmpty ? "Subtitle" : track.language.uppercased()) { model.selectSubtitle(track) }
                    }
                } label: { Image(systemName: model.subtitle == nil ? "captions.bubble" : "captions.bubble.fill").font(.title3) }
            }
            if model.videos.count > 1 {
                Menu {
                    ForEach(model.videos) { track in
                        Button {
                            model.select(track)
                        } label: {
                            if track.id == model.selected?.id {
                                Label(track.quality.isEmpty ? "Auto" : track.quality, systemImage: "checkmark")
                            } else {
                                Text(track.quality.isEmpty ? "Auto" : track.quality)
                            }
                        }
                    }
                } label: { Image(systemName: "slider.horizontal.3").font(.title3) }
            }
            if nextEpisode != nil {
                Button { Task { await playNext() } } label: {
                    if isLoadingNext { ProgressView().tint(.white) } else { Image(systemName: "forward.end.fill").font(.title3) }
                }
                .disabled(isLoadingNext)
            }
        }
        .foregroundStyle(.white)
        .padding()
    }

    private func nextCard(_ next: Episode) -> some View {
        VStack(spacing: 10) {
            Text("Episode berikutnya").font(.caption).foregroundStyle(.secondary)
            Text(next.title).font(.headline).lineLimit(1)
            HStack {
                Button { Task { await playNext() } } label: {
                    Text(countdown.map { "Putar sekarang (\($0))" } ?? "Putar sekarang")
                }
                .buttonStyle(.borderedProminent)
                Button("Batal") { model.ended = false; countdown = nil }
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 48)
    }

    private func playNext() async {
        guard let next = nextEpisode, !isLoadingNext else { return }
        countdown = nil
        isLoadingNext = true
        defer { isLoadingNext = false }
        model.report()
        if let request = await loadEpisode(next) {
            current = request
            model.load(request)
        } else {
            model.ended = false
        }
    }
}

/// Presented by DetailView; builds the closures from the environment inside a real view body.
struct PlayerHost: View {
    let content: Content
    let request: PlayerRequest
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var streams: StreamRepository
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let service = PlaybackService(store: store, streams: streams)
        let localStore = store
        PlayerView(content: content, request: request, preferredQuality: settings.preferredQuality,
                   loadEpisode: { await service.request(content: content, episode: $0) },
                   onProgress: { req, position, duration in
                       localStore.savePosition(content: content, episode: req.episode, position: position, duration: duration)
                   })
    }
}
