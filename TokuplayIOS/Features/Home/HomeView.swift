import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var repo: ContentRepository
    @EnvironmentObject private var store: LocalStore
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            Group {
                switch repo.phase {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ErrorState(message: message) { Task { await repo.load(api: settings.api) } }
                case .loaded:
                    loaded
                }
            }
            .navigationTitle("Tokuplay")
            .refreshable { await repo.load(api: settings.api) }
            .task(id: settings.baseURLString) { await repo.load(api: settings.api) }
        }
    }

    @ViewBuilder private var loaded: some View {
        let tabs = repo.tabs
        if tabs.isEmpty {
            // No site config: show every post.
            if repo.all.isEmpty { ErrorState(message: "Belum ada konten.") } else { ContentGrid(items: repo.all) }
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                            Button(tab.title) { selectedTab = i }
                                .buttonStyle(.bordered)
                                .tint(i == min(selectedTab, tabs.count - 1) ? .accentColor : .secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                TabSections(tab: tabs[min(selectedTab, tabs.count - 1)])
                    .navigationDestination(for: Content.self) { DetailView(content: $0) }
            }
        }
    }
}

private struct TabSections: View {
    let tab: HomeTab
    @EnvironmentObject private var repo: ContentRepository
    @EnvironmentObject private var store: LocalStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(tab.groups.filter { repo.isRenderable($0) }) { group in
                    section(for: group)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder private func section(for group: HomeGroup) -> some View {
        if group.type == "7" {
            if let text = group.description, !text.isEmpty {
                Text(text).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
        } else {
            let items = repo.items(for: group, history: store.history)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title ?? tab.title).font(.headline).padding(.horizontal)
                    if group.type == "2" {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                            ForEach(items) { item in
                                NavigationLink(value: item) { ContentCard(item: item) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(items) { item in
                                    NavigationLink(value: item) { ContentCard(item: item).frame(width: 110) }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
}
