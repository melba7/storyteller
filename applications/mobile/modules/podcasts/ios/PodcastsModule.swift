// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// It fetches a podcast feed and reads it with PodcastFeed (libraries/PodcastKit), and plays
// episodes with PodcastPlayer. The library of shows and episodes is kept by the app's
// JavaScript in its own SQLite file (podcasts/ and modules/podcasts/db.ts).

import ExpoModulesCore
import Foundation
import PodcastAds
import PodcastDownloads
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
  @Field var audioType: String = ""
  @Field var showId: String?
  @Field var chaptersUrl: String?
  /// Play from the episode's own download as it arrives (Skip ads is on and it is not downloaded).
  @Field var playThroughDownload: Bool = false
  /// The feed's language, for the transcript of the download that plays.
  @Field var language: String?
}

/// An episode to put in Up Next.
struct UpNextItemOptions: Record {
  @Field var id: String = ""
  @Field var url: String = ""
  @Field var type: String = ""
  @Field var title: String = ""
  @Field var showTitle: String = ""
  @Field var artworkUrl: String?
  @Field var duration: Double?
  @Field var position: Double = 0
  @Field var showId: String?
  @Field var chaptersUrl: String?
}

public final class PodcastsModule: Module {
  public func definition() -> ModuleDefinition {
    Name("Podcasts")

    Events("onPlaybackState", "onPlaybackEnded", "onPlaybackError", "onDownloadChange",
      "onUpNextChange", "onPlaybackAdvanced", "onTranscriptChange", "onSleepTimerChange",
      "onAdsChange", "onAdSkipped", "onAdUndone", "onChaptersChange", "onBookmarksPending")

    OnCreate {
      PodcastDownloader.shared.setSink { [weak self] name, body in self?.sendEvent(name, body) }
      PodcastDownloader.shared.start()
      PodcastTranscriber.shared.setSink { [weak self] name, body in self?.sendEvent(name, body) }
      PodcastTranscriber.shared.start()
      PodcastAdFinder.shared.setSink { [weak self] name, body in self?.sendEvent(name, body) }
      PodcastAdFinder.shared.start()
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
        duration: options.duration, played: options.played, autoplay: options.autoplay,
        type: options.audioType, showId: options.showId, chaptersUrl: options.chaptersUrl,
        playThroughDownload: options.playThroughDownload, language: options.language)
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
      let amount = Double(PlaybackSettingsStore.current.skipForward)
      await MainActor.run { PodcastPlayer.shared.skip(by: amount) }
    }
    AsyncFunction("skipBack") { () async in
      let amount = PlaybackSettingsStore.current.previousSeconds
      await MainActor.run { PodcastPlayer.shared.skip(by: -amount) }
    }

    // Sets the speed, rounded to 0.1 within 0.5 to 3.0, and returns the speed in use.
    AsyncFunction("setRate") { (rate: Double) async -> Double in
      await MainActor.run { PodcastPlayer.shared.setRate(rate) }
    }

    AsyncFunction("getPlaybackState") { () async -> [String: Any] in
      await MainActor.run { PodcastPlayer.shared.state() }
    }

    // MARK: Up Next

    AsyncFunction("listUpNext") { () async -> [[String: Any]] in
      await MainActor.run { PodcastPlayer.shared.upNextObjects() }
    }
    // Puts an episode at the top ("next") or the bottom ("last"). One already queued moves.
    AsyncFunction("addToUpNext") { (item: UpNextItemOptions, place: String) async throws in
      guard let place = QueuePlace(rawValue: place), !item.id.isEmpty else {
        throw PodcastFetchError(message: "This episode can't be added to Up Next.")
      }
      let queued = QueueItem(
        id: item.id, url: item.url, type: item.type, title: item.title,
        showTitle: item.showTitle, artworkUrl: item.artworkUrl, duration: item.duration,
        position: item.position, showId: item.showId, chaptersUrl: item.chaptersUrl)
      await MainActor.run { PodcastPlayer.shared.addToUpNext(queued, at: place) }
    }
    AsyncFunction("moveInUpNext") { (from: Int, to: Int) async in
      await MainActor.run { PodcastPlayer.shared.moveInUpNext(from: from, to: to) }
    }
    AsyncFunction("removeFromUpNext") { (id: String) async in
      await MainActor.run { PodcastPlayer.shared.removeFromUpNext(id) }
    }
    AsyncFunction("clearUpNext") { () async in
      await MainActor.run { PodcastPlayer.shared.clearUpNext() }
    }

    // MARK: Notifications

    // "granted", "denied" or "undetermined".
    AsyncFunction("notificationPermission") { () async -> String in
      await PodcastNotifier.shared.permission()
    }
    // Asks the listener (iOS shows its question the first time); returns whether it is allowed.
    AsyncFunction("requestNotificationPermission") { () async -> Bool in
      await PodcastNotifier.shared.requestPermission()
    }
    // Posts a notification now. Nothing happens without permission.
    AsyncFunction("postNotification") { (id: String, title: String, body: String) async throws in
      do {
        try await PodcastNotifier.shared.post(id: id, title: title, body: body)
      } catch {
        throw PodcastFetchError(message: error.localizedDescription)
      }
    }

    // MARK: AirPlay

    // The system's AirPlay button, for the player (see AirPlayRouteView).
    View(AirPlayRouteView.self) {
      Prop("label") { (view: AirPlayRouteView, label: String) in view.setLabel(label) }
    }

    // MARK: Playback settings

    // The listener's playback settings (see PlaybackSettings). Saving returns what was kept.
    AsyncFunction("getPlaybackSettings") { () -> [String: Any] in
      PlaybackSettingsStore.current.values
    }
    AsyncFunction("setPlaybackSettings") { (values: [String: Any]) async -> [String: Any] in
      let kept = PlaybackSettingsStore.save(values)
      await MainActor.run { PodcastPlayer.shared.settingsChanged() }
      return kept.values
    }

    // MARK: Bookmarks

    // The bookmarks the headphones made while the app wasn't running, as a JSON list (see
    // PendingBookmarks). The app saves them, then asks to remove the ones it saved.
    AsyncFunction("readPendingBookmarks") { () async -> String in
      await MainActor.run { PodcastPlayer.readPendingBookmarks() }
    }
    AsyncFunction("removePendingBookmarks") { (ids: [String]) async throws in
      try await MainActor.run { try PodcastPlayer.removePendingBookmarks(ids: ids) }
    }

    // MARK: Sleep timer

    // A countdown in minutes (1 to 720), or until the end of the episode. Both replace any
    // timer. The state is "none", "countdown" (with `endsAt`, milliseconds) or "endOfEpisode".
    AsyncFunction("startSleepTimer") { (minutes: Double) async throws in
      let started = await MainActor.run { PodcastPlayer.shared.startSleep(minutes: minutes) }
      if !started { throw PodcastFetchError(message: "That is not a time the timer can use.") }
    }
    AsyncFunction("sleepUntilEndOfEpisode") { () async in
      await MainActor.run { PodcastPlayer.shared.sleepUntilEndOfEpisode() }
    }
    AsyncFunction("sleepUntilEndOfChapter") { () async throws in
      let started = await MainActor.run { PodcastPlayer.shared.sleepUntilEndOfChapter() }
      if !started { throw PodcastFetchError(message: "This episode has no chapter playing now.") }
    }
    AsyncFunction("extendSleepTimer") { () async in
      await MainActor.run { PodcastPlayer.shared.extendSleep() }
    }
    AsyncFunction("cancelSleepTimer") { () async in
      await MainActor.run { PodcastPlayer.shared.cancelSleep() }
    }
    AsyncFunction("getSleepTimer") { () async -> [String: Any] in
      await MainActor.run { PodcastPlayer.shared.sleepObject() }
    }

    // MARK: Chapters

    // The loaded episode's chapters (they are also sent with `onChaptersChange`), the previous
    // and next chapter buttons, and the switch that skips a chapter (`start` in seconds).
    AsyncFunction("getChapters") { () async -> [String: Any] in
      await MainActor.run { PodcastPlayer.shared.chaptersInfo() }
    }
    AsyncFunction("previousChapter") { () async in
      await MainActor.run { PodcastPlayer.shared.previousChapter() }
    }
    AsyncFunction("nextChapter") { () async in
      await MainActor.run { _ = PodcastPlayer.shared.nextChapter() }
    }
    AsyncFunction("setChapterSkipped") { (episodeId: String, start: Double, skipped: Bool) async in
      await MainActor.run {
        PodcastPlayer.shared.setChapterSkipped(episodeId: episodeId, start: start, skipped: skipped)
      }
    }

    // MARK: Downloading

    // Starts downloading an episode; carries on with the app closed. `type` is the feed's
    // audio type, used to name the file. `automatic` marks a new episode the app fetches by
    // itself: those always wait for Wi-Fi. `language` is the feed's, for the transcript.
    AsyncFunction("download") {
      (episodeId: String, url: String, type: String, automatic: Bool, language: String?) throws in
      PodcastTranscriber.shared.noteLanguage(language, for: episodeId)
      do {
        try PodcastDownloader.shared.download(
          episodeId: episodeId, url: url, type: type, automatic: automatic)
      } catch {
        throw PodcastFetchError(message: error.localizedDescription)
      }
    }
    // Adds an audio file picked in the Files app: copies it in and installs it like a finished
    // download. Resolves with the episode's id, title, length, size and extension.
    AsyncFunction("importAudioFile") { (uri: String, fileName: String?) async throws -> [String: Any] in
      do {
        return try await PodcastDownloader.shared.importAudioFile(uri: uri, fileName: fileName)
      } catch let error as PodcastFetchError {
        throw error
      } catch {
        throw PodcastFetchError(message: error.localizedDescription)
      }
    }
    // Stops a download that is not finished and forgets it.
    AsyncFunction("cancelDownload") { (episodeId: String) throws in
      try PodcastDownloader.shared.cancel(episodeId: episodeId)
    }
    // Removes a download: the audio, its side files and its entry.
    AsyncFunction("deleteDownload") { (episodeId: String) throws in
      try PodcastDownloader.shared.remove(episodeId: episodeId)
    }
    AsyncFunction("listDownloads") { () -> [[String: Any]] in
      (PodcastDownloader.shared.store?.entries() ?? []).map(DownloadJSON.object)
    }
    // Bytes taken by finished downloads.
    AsyncFunction("storageUsed") { () -> Double in
      Double(PodcastDownloader.shared.store?.storageUsed() ?? 0)
    }
    AsyncFunction("setWifiOnly") { (on: Bool) in DownloadSettings.wifiOnly = on }
    AsyncFunction("getWifiOnly") { () -> Bool in DownloadSettings.wifiOnly }

    // MARK: Show settings

    // Saves the settings of every show the player must know with the screen locked (speed,
    // intro, outro, skip switches) as one JSON object keyed by show id.
    AsyncFunction("writeShowSettings") { (json: String) async throws in
      guard ShowSettingsStore.write(json: json) else {
        throw PodcastFetchError(message: "The show settings could not be saved.")
      }
      // The loaded show's sound choices may have changed.
      await MainActor.run { PodcastPlayer.shared.applyShowSound() }
    }

    // Seconds of audio that silence trimming has cut so far (for a stats screen).
    AsyncFunction("getTrimSavings") { () -> Double in TrimSavingsStore.seconds }

    // The listening stats, counted here so they count with the screen locked.
    AsyncFunction("getStats") { () -> [String: Any] in StatsStore.shared.object() }
    AsyncFunction("resetStats") { () in StatsStore.shared.reset() }

    // MARK: Transcripts

    // Every downloaded episode's transcript state, and one finished transcript as JSON.
    AsyncFunction("listTranscripts") { () -> [[String: Any]] in PodcastTranscriber.shared.all() }
    AsyncFunction("getTranscript") { (episodeId: String) -> String? in
      PodcastTranscriber.shared.transcriptJSON(episodeId)
    }
    // The lines of a transcript that is still being made, as JSON, or nil.
    AsyncFunction("getPartialTranscript") { (episodeId: String) -> String? in
      PodcastTranscriber.shared.partialJSON(episodeId)
    }
    // The words said in every finished transcript: hits with the episode, time and line.
    AsyncFunction("searchTranscripts") { (query: String) async -> [[String: Any]] in
      await PodcastTranscriber.shared.search(query)
    }

    // MARK: Ads

    // Where every transcribed episode's ad finding is, and one episode's saved ads as JSON.
    AsyncFunction("listAds") { () -> [[String: Any]] in PodcastAdFinder.shared.all() }
    AsyncFunction("getAds") { (episodeId: String) -> String? in
      PodcastAdFinder.shared.adsJSON(episodeId)
    }

    // The two switches for skipping ads and the hosts' own plugs (both on until turned off).
    AsyncFunction("getAdSkipSettings") { () -> [String: Bool] in
      let settings = AdSkipDefaults.settings
      return ["skipAds": settings.skipAds, "skipOwnPlugs": settings.skipOwnPlugs]
    }
    AsyncFunction("setAdSkipSettings") { (skipAds: Bool, skipOwnPlugs: Bool) async in
      AdSkipDefaults.settings = AdSkipSettings(skipAds: skipAds, skipOwnPlugs: skipOwnPlugs)
      await MainActor.run { PodcastPlayer.shared.adSkipping.refresh() }
    }
    // Takes back the skip that was just made: back to the ad's start, playing, and the skip is
    // recorded as wrong. False when it is too late.
    AsyncFunction("undoAdSkip") { () async -> Bool in
      await MainActor.run { PodcastPlayer.shared.adSkipping.undo() }
    }

    // The main colour of a picture as "#rrggbb", or null when it can't be read.
    AsyncFunction("artworkColor") { (address: String) async -> String? in
      guard let url = URL(string: address) else { return nil }
      return await artworkColor(url)
    }
  }
}
