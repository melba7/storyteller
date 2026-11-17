// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// It fetches a podcast feed and reads it with PodcastFeed (libraries/PodcastKit), and plays
// episodes with PodcastPlayer. The library of shows and episodes is kept by the app's
// JavaScript in its own SQLite file (podcasts/ and modules/podcasts/db.ts).

import ExpoModulesCore
import Foundation
import PodcastFeed
import PodcastPlayback

/// What the app asks the player to load.
struct PlaybackLoadOptions: Record {
  @Field var episodeId: String = ""
  @Field var url: String = ""
  @Field var title: String = ""
  @Field var showTitle: String = ""
  @Field var artworkUrl: String?
  @Field var savedPosition: Double = 0
  @Field var duration: Double?
  @Field var played: Bool = false
  @Field var autoplay: Bool = true
}

public final class PodcastsModule: Module {
  public func definition() -> ModuleDefinition {
    Name("Podcasts")

    Events("onPlaybackState", "onPlaybackEnded", "onPlaybackError")

    OnCreate {
      Task { @MainActor [weak self] in
        PodcastPlayer.shared.sink = { name, body in self?.sendEvent(name, body) }
      }
    }

    // Downloads the feed at this address and reads it. Rejects with a message the listener
    // can read: a bad link, no connection, the server's status, a feed that is too big or
    // a page that is not a podcast feed.
    AsyncFunction("fetchFeed") { (url: String) async throws -> [String: Any] in
      do {
        let data = try await PodcastFeedFetcher.download(url)
        let feed = try FeedParser.parse(data)
        return PodcastFeedJSON.object(feed)
      } catch {
        throw NSError(domain: "Podcasts", code: 1, userInfo: [
          NSLocalizedDescriptionKey: error.localizedDescription,
        ])
      }
    }

    // MARK: Playing

    // Loads an episode and, unless told not to, starts it. It starts at the saved place unless
    // the episode was played or was nearly over.
    AsyncFunction("load") { (options: PlaybackLoadOptions) async throws in
      guard let url = URL(string: options.url), let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https", url.host != nil
      else {
        throw PodcastFetchError(message: "This episode has no playable link.")
      }
      let episode = PodcastPlayer.Episode(
        id: options.episodeId, url: url, title: options.title, showTitle: options.showTitle,
        artworkUrl: options.artworkUrl, savedPosition: options.savedPosition,
        duration: options.duration, played: options.played, autoplay: options.autoplay)
      await MainActor.run { PodcastPlayer.shared.load(episode) }
    }

    AsyncFunction("play") { () async in await MainActor.run { PodcastPlayer.shared.play() } }
    AsyncFunction("pause") { () async in await MainActor.run { PodcastPlayer.shared.pause() } }
    AsyncFunction("togglePlayPause") { () async in
      await MainActor.run { PodcastPlayer.shared.togglePlayPause() }
    }
    AsyncFunction("seekTo") { (seconds: Double) async in
      await MainActor.run { PodcastPlayer.shared.seek(to: seconds) }
    }
    AsyncFunction("skipBy") { (seconds: Double) async in
      await MainActor.run { PodcastPlayer.shared.skip(by: seconds) }
    }
    AsyncFunction("skipForward") { () async in
      await MainActor.run { PodcastPlayer.shared.skip(by: Skip.ahead) }
    }
    AsyncFunction("skipBack") { () async in
      await MainActor.run { PodcastPlayer.shared.skip(by: -Skip.back) }
    }

    // Sets the speed, rounded to 0.1 within 0.5 to 3.0, and returns the speed in use.
    AsyncFunction("setRate") { (rate: Double) async -> Double in
      await MainActor.run { PodcastPlayer.shared.setRate(rate) }
    }

    AsyncFunction("getPlaybackState") { () async -> [String: Any] in
      await MainActor.run { PodcastPlayer.shared.state() }
    }

    // The main colour of a picture as "#rrggbb", or null when it can't be read.
    AsyncFunction("artworkColor") { (address: String) async -> String? in
      guard let url = URL(string: address) else { return nil }
      return await artworkColor(url)
    }
  }
}
