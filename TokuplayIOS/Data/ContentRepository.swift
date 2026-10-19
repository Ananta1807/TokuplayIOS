import Foundation

/// Loads every post once (the blog has ~540) and builds the home sections described by the site config.
@MainActor
final class ContentRepository: ObservableObject {
    enum Phase { case idle, loading, loaded, failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var all: [Content] = []
    @Published private(set) var config: SiteConfig?

    private var byPostID: [String: Content] = [:]
    private var byID: [String: Content] = [:]

    func load(api: ApiService?) async {
        guard let api else {
            phase = .failed("Alamat sumber konten belum diatur. Buka tab Pengaturan.")
            return
        }
        phase = .loading
        do {
            let posts = try await api.fetchAll()
            // The site config is optional: without it Home falls back to a plain list.
            config = try? await ConfigService.fetch(baseURL: api.baseURL, session: api.session)
            all = posts
            byPostID = Dictionary(posts.map { ($0.postID, $0) }, uniquingKeysWith: { a, _ in a })
            byID = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Tabs worth showing: groups that are enabled and that this port can render (live TV channels are skipped).
    var tabs: [HomeTab] {
        (config?.tabs ?? []).filter { tab in tab.groups.contains { isRenderable($0) } }
    }

    func isRenderable(_ g: HomeGroup) -> Bool { g.isEnabled && g.target != "#DIR" }

    func items(for group: HomeGroup, history: [HistoryEntry]) -> [Content] {
        var result: [Content]
        switch group.target {
        case "#POP": result = (config?.popularIDs ?? []).compactMap { byPostID[$0] }
        case "#HIS": result = history.compactMap { byID[$0.contentID] }
        case "#PIC": result = (group.picks ?? []).compactMap { byPostID[$0] }
        default:
            let labels = group.labels ?? []
            result = labels.isEmpty ? [] : all.filter { c in labels.allSatisfy { c.labels.contains($0) } }
        }
        if let limit = group.maxItems { result = Array(result.prefix(limit)) }
        return result
    }
}
