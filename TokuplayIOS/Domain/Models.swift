import Foundation

struct Content: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var summary: String?
    var imageURL: URL?
    var published: Date?
    var labels: [String]
    var pageURL: URL?
    var episodes: [Episode]
    var rating: String? = nil
    var info: String? = nil
    var fansub: String? = nil
    /// Post ids chosen by hand on the blog ("relatedList"); nil when the post uses automatic matching.
    var relatedIDs: [String]? = nil

    /// Numeric Blogger post id (what the site config uses in `picks` and `.popular`).
    var postID: String { id.components(separatedBy: "post-").last ?? id }
}

struct Episode: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var servers: [Server]
}

/// Port of com.androidku.tokuplay.domain.model.Server
struct Server: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var sources: [Source]
    var subtitles: [String]
    var referer: String
}
