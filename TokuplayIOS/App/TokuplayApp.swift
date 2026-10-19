import SwiftUI

@main
struct TokuplayApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = LocalStore()
    @StateObject private var streams = StreamRepository()
    @StateObject private var repo = ContentRepository()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(streams)
                .environmentObject(repo)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house") }
            SearchView().tabItem { Label("Cari", systemImage: "magnifyingglass") }
            LibraryView().tabItem { Label("Koleksi", systemImage: "bookmark") }
            SettingsView().tabItem { Label("Pengaturan", systemImage: "gear") }
        }
    }
}

/// Shared by Home / Search / Library: poster grid that pushes DetailView.
struct ContentGrid: View {
    let items: [Content]
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: item) { ContentCard(item: item) }.buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationDestination(for: Content.self) { DetailView(content: $0) }
    }
}

struct ContentCard: View {
    let item: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Color.secondary.opacity(0.2).overlay(Image(systemName: "film").foregroundStyle(.secondary))
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.title).font(.caption).lineLimit(2).multilineTextAlignment(.leading)
        }
    }
}

struct ErrorState: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        ContentUnavailableView {
            Label("Tidak tersedia", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            if let retry { Button("Coba lagi", action: retry) }
        }
    }
}
