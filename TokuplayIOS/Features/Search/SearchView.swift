import SwiftUI

/// Searches the posts already loaded by ContentRepository (the whole blog, ~540 posts), so it is instant,
/// matches partial words and tolerates a missing letter ("zetz" finds "Zeztz").
struct SearchView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var repo: ContentRepository
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                switch repo.phase {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ErrorState(message: message) { Task { await repo.load(api: settings.api) } }
                case .loaded:
                    let results = Self.search(query, in: repo.all)
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView("Cari tontonan", systemImage: "magnifyingglass")
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ContentGrid(items: results)
                    }
                }
            }
            .navigationTitle("Cari")
            .searchable(text: $query, prompt: "Judul")
            .task {
                if case .idle = repo.phase { await repo.load(api: settings.api) }
            }
        }
    }

    // MARK: - Matching

    /// 1) title or label contains the query, 2) otherwise the query's letters appear in order in the title.
    static func search(_ query: String, in items: [Content]) -> [Content] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        let direct = items.filter { c in
            normalize(c.title).contains(q) || c.labels.contains { normalize($0).contains(q) }
        }
        if !direct.isEmpty || q.count < 3 { return direct }
        return items.filter { isSubsequence(q, of: normalize($0.title)) }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        for ch in needle {
            var found = false
            while let h = it.next() { if h == ch { found = true; break } }
            if !found { return false }
        }
        return true
    }
}
