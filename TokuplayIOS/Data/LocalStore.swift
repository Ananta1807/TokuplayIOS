import Foundation

/// Replacement for the APK's Room database (BookmarkDao / HistoryDao).
struct HistoryEntry: Codable, Hashable, Identifiable {
    var id: String { contentID }
    let contentID: String
    var episodeID: String
    var episodeTitle: String
    var positionSeconds: Double
    var updated: Date
}

@MainActor
final class LocalStore: ObservableObject {
    @Published private(set) var bookmarks: [Content] = []
    @Published private(set) var history: [HistoryEntry] = []

    private let defaults: UserDefaults
    private let bookmarkKey = "bookmarks.v1"
    private let historyKey = "history.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmarks = Self.load([Content].self, defaults, bookmarkKey) ?? []
        history = Self.load([HistoryEntry].self, defaults, historyKey) ?? []
    }

    func isBookmarked(_ c: Content) -> Bool { bookmarks.contains { $0.id == c.id } }

    func toggleBookmark(_ c: Content) {
        if let i = bookmarks.firstIndex(where: { $0.id == c.id }) {
            bookmarks.remove(at: i)
        } else {
            bookmarks.insert(c, at: 0)
        }
        save(bookmarks, bookmarkKey)
    }

    func record(content: Content, episode: Episode, position: Double = 0) {
        history.removeAll { $0.contentID == content.id }
        history.insert(HistoryEntry(contentID: content.id, episodeID: episode.id, episodeTitle: episode.title,
                                    positionSeconds: position, updated: Date()), at: 0)
        history = Array(history.prefix(200))
        save(history, historyKey)
    }

    func entry(for c: Content) -> HistoryEntry? { history.first { $0.contentID == c.id } }

    func clearAll() {
        bookmarks = []
        history = []
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: historyKey)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ d: UserDefaults, _ key: String) -> T? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
