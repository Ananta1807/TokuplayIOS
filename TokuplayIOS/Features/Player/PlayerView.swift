import SwiftUI
import AVKit

struct PlayerRequest: Identifiable {
    let id = UUID()
    let title: String
    let stream: StreamResult
}

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    let videos: [VideoTrack]
    let subtitleTracks: [SubtitleTrack]
    @Published var selected: VideoTrack?
    @Published var subtitle: SubtitleTrack?
    @Published var subtitleText: String?

    private var cues: [SubtitleCue] = []
    private var timeObserver: Any?
    private var loadTask: Task<Void, Never>?

    init(stream: StreamResult) {
        videos = stream.videos.filter { $0.resolvedURL != nil }
        subtitleTracks = stream.subtitles.filter { $0.resolvedURL != nil }
        if let first = videos.first { select(first) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.updateSubtitle(at: time.seconds) }
        }
        if let first = subtitleTracks.first { selectSubtitle(first) }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    /// Keeps the playback position when the user switches quality.
    func select(_ track: VideoTrack) {
        guard let url = track.resolvedURL else { return }
        let resume = player.currentTime()
        var options: [String: Any] = [:]
        if !track.headers.isEmpty {
            // Widely used key for per-request headers (e.g. Referer); not exposed as a public constant.
            options["AVURLAssetHTTPHeaderFieldsKey"] = track.headers
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: url, options: options)))
        if resume.isValid && resume.seconds > 0 { player.seek(to: resume) }
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

    private func updateSubtitle(at time: Double) {
        let text = cues.isEmpty ? nil : SubtitleParser.cue(at: time, in: cues)?.text
        if text != subtitleText { subtitleText = text }
    }
}

struct PlayerView: View {
    let request: PlayerRequest
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    init(request: PlayerRequest) {
        self.request = request
        _model = StateObject(wrappedValue: PlayerModel(stream: request.stream))
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

            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                Text(request.title).font(.subheadline).lineLimit(1)
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
                            Button(track.quality.isEmpty ? "Auto" : track.quality) { model.select(track) }
                        }
                    } label: { Image(systemName: "slider.horizontal.3").font(.title3) }
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
        .onDisappear { model.player.pause() }
    }
}
