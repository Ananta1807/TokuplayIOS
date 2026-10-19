import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""
    @State private var results: [Content] = []
    @State private var error: String?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ErrorState(message: error)
                } else if isSearching {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Cari tontonan" : "Tidak ada hasil",
                                           systemImage: "magnifyingglass")
                } else {
                    ContentGrid(items: results)
                }
            }
            .navigationTitle("Cari")
            .searchable(text: $query, prompt: "Judul")
            .task(id: query) { await search() }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; error = nil; return }
        guard let api = settings.api else { error = "Alamat sumber konten belum diatur."; return }
        // Debounce: task(id:) cancels this sleep when the text changes again.
        do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await api.fetchPage(query: q).items
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
