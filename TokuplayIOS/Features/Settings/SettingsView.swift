import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LocalStore
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://contoh.blogspot.com", text: $settings.baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if !settings.baseURLString.isEmpty && settings.baseURL == nil {
                        Label("URL tidak valid", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                } header: {
                    Text("Sumber konten (Blogger)")
                } footer: {
                    Text("Alamat blog yang menyediakan feed /feeds/posts/default?alt=json.")
                }

                Section {
                    Picker("Kualitas default", selection: $settings.preferredQuality) {
                        Text("Tertinggi").tag(0)
                        Text("1080p").tag(1080)
                        Text("720p").tag(720)
                        Text("480p").tag(480)
                    }
                } header: {
                    Text("Pemutar")
                } footer: {
                    Text("Dipakai bila episode punya beberapa kualitas. Bisa diganti saat memutar.")
                }

                Section("Data lokal") {
                    Text("\(store.bookmarks.count) bookmark, \(store.history.count) riwayat")
                    Button("Hapus bookmark & riwayat", role: .destructive) { confirmClear = true }
                }

                Section("Tentang") {
                    LabeledContent("Versi", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("Pengaturan")
            .confirmationDialog("Hapus semua bookmark dan riwayat?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Hapus", role: .destructive) { store.clearAll() }
            }
        }
    }
}
