import Foundation

/// The content backend (a Blogger blog) is not hard-coded: it is user supplied,
/// or preset in Info.plist (TokuplayBaseURL).
final class AppSettings: ObservableObject {
    private static let key = "contentBaseURL"

    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.key) }
    }

    /// 0 = highest available, otherwise the highest quality that does not exceed this height (1080, 720, 480).
    @Published var preferredQuality: Int {
        didSet { UserDefaults.standard.set(preferredQuality, forKey: "preferredQuality") }
    }

    init() {
        preferredQuality = UserDefaults.standard.integer(forKey: "preferredQuality")
        let preset = Bundle.main.object(forInfoDictionaryKey: "TokuplayBaseURL") as? String ?? ""
        baseURLString = UserDefaults.standard.string(forKey: Self.key) ?? preset
    }

    var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    var api: ApiService? { baseURL.map { ApiService(baseURL: $0) } }
}
