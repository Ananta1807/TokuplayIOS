import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: LocalStore

    var body: some View {
        NavigationStack {
            Group {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("Belum ada bookmark", systemImage: "bookmark",
                                           description: Text("Simpan tontonan dari halaman detail."))
                } else {
                    ContentGrid(items: store.bookmarks)
                }
            }
            .navigationTitle("Koleksi")
        }
    }
}

struct DetailView: View {
    let content: Content
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var streams: StreamRepository
    @State private var playing: PlayerRequest?
    @State private var loadingEpisode: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ContentCard(item: content).frame(maxWidth: 160)
                    let facts = [content.info, content.rating.map { "★ \($0)" }, content.fansub.map { "Sumber: \($0)" }].compactMap { $0 }
                    if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.footnote) }
                    if !content.labels.isEmpty {
                        Text(content.labels.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let summary = content.summary { Text(summary).font(.callout).lineLimit(8) }
                    if let published = content.published {
                        Text(published.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Episode") {
                if content.episodes.isEmpty {
                    Text("Belum ada episode yang bisa diputar.").foregroundStyle(.secondary)
                }
                ForEach(content.episodes) { episode in
                    let reason = StreamSupport.explanation(for: episode)
                    Button {
                        if let reason { errorMessage = reason } else { Task { await play(episode) } }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.title).foregroundStyle(reason == nil ? .primary : .secondary)
                                if reason != nil { Text("Belum didukung di iOS").font(.caption2).foregroundStyle(.orange) }
                            }
                            Spacer()
                            if loadingEpisode == episode.id {
                                ProgressView()
                            } else {
                                Image(systemName: reason == nil ? "play.circle" : "exclamationmark.circle").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(loadingEpisode != nil)
                }
            }
        }
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { store.toggleBookmark(content) } label: {
                Image(systemName: store.isBookmarked(content) ? "bookmark.fill" : "bookmark")
            }
        }
        .fullScreenCover(item: $playing) { PlayerView(request: $0) }
        .alert("Tidak bisa diputar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    /// Tries each server of the episode in order and plays the first one that yields a video.
    private func play(_ episode: Episode) async {
        loadingEpisode = episode.id
        defer { loadingEpisode = nil }
        for server in episode.servers {
            let result = await streams.extract(sources: server.sources, serverName: server.name, serverId: server.id,
                                               serverReferer: server.referer, subtitleURLs: server.subtitles)
            if !result.videos.isEmpty {
                store.record(content: content, episode: episode)
                playing = PlayerRequest(title: "\(content.title) – \(episode.title)", stream: result)
                return
            }
        }
        errorMessage = "Sumber video tidak bisa dimuat. Periksa koneksi, lalu coba lagi."
    }
}
