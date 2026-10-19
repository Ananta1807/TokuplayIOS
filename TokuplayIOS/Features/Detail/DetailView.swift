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
    @EnvironmentObject private var repo: ContentRepository
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
                                if reason != nil {
                                    Text("Belum didukung di iOS").font(.caption2).foregroundStyle(.orange)
                                } else if let resume = Self.resumeLabel(store.resumePosition(for: content, episode: episode)) {
                                    Text("Lanjut \(resume)").font(.caption2).foregroundStyle(.secondary)
                                }
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
            let related = repo.related(to: content)
            if !related.isEmpty {
                Section("Terkait") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(related) { item in
                                NavigationLink(value: item) { ContentCard(item: item).frame(width: 110) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
        .fullScreenCover(item: $playing) { PlayerHost(content: content, request: $0) }
        .alert("Tidak bisa diputar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func play(_ episode: Episode) async {
        loadingEpisode = episode.id
        defer { loadingEpisode = nil }
        let service = PlaybackService(store: store, streams: streams)
        if let request = await service.request(content: content, episode: episode) {
            playing = request
        } else {
            errorMessage = "Sumber video tidak bisa dimuat. Periksa koneksi, lalu coba lagi."
        }
    }

    /// "12:34" or "1:02:03"; nil when there is nothing to resume.
    private static func resumeLabel(_ seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        let t = Int(seconds)
        let (h, m, s) = (t / 3600, t % 3600 / 60, t % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
