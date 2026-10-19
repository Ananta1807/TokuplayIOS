import Foundation

/// Resolves an episode into something the player can play, and records it in the watch history.
@MainActor
struct PlaybackService {
    let store: LocalStore
    let streams: StreamRepository

    /// Tries each server of the episode in order and returns the first one that yields a video.
    func request(content: Content, episode: Episode) async -> PlayerRequest? {
        let start = store.resumePosition(for: content, episode: episode)
        for server in episode.servers {
            let result = await streams.extract(sources: server.sources, serverName: server.name, serverId: server.id,
                                               serverReferer: server.referer, subtitleURLs: server.subtitles)
            if !result.videos.isEmpty {
                store.record(content: content, episode: episode, position: start)
                return PlayerRequest(title: "\(content.title) – \(episode.title)", stream: result,
                                     episode: episode, startAt: start)
            }
        }
        return nil
    }
}
