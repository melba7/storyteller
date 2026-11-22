// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The chapters of the episode the player has loaded, in Swift so they work with the screen
// locked and with Up Next moving on with no JavaScript. On load it reads the downloaded file's
// chapters and the feed's JSON chapters (PodcastChapterSource); the rules (the feed wins, which
// chapter is playing, previous and next, which to skip) are PodcastChapters'. Chapters the
// listener switched off are jumped over as playback reaches them, but never after a seek.

import AVFoundation
import Foundation
import PodcastChapters
import PodcastPlayback

/// The loaded episode's chapters. Kept here so PodcastPlayer.swift needs no new properties.
@MainActor
final class ChapterState {
  static let shared = ChapterState()
  var episodeId: String?
  var chapters: [Chapter] = []
  var skipper = ChapterSkipper()
  var loading: Task<Void, Never>?
  /// A jump over a skipped chapter is under way.
  var jumping = false
}

/// The chapters the listener switched off, per episode, in the app's defaults so the player
/// reads them with no JavaScript running.
enum ChapterSkipStore {
  private static let key = "podcasts.chapterSkips"

  static func skipped(for episodeId: String) -> Set<Int> {
    let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [Int]] ?? [:]
    return Set(all[episodeId] ?? [])
  }

  static func save(_ skipped: Set<Int>, for episodeId: String) {
    var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [Int]] ?? [:]
    all[episodeId] = skipped.isEmpty ? nil : skipped.sorted()
    UserDefaults.standard.set(all, forKey: key)
  }
}

@MainActor
extension PodcastPlayer {
  // MARK: Loading

  /// An episode was loaded, to start at `position`: forget the last one's chapters and read
  /// this one's.
  func beginChapters(_ episode: Episode, startingAt position: Double) {
    let state = ChapterState.shared
    state.loading?.cancel()
    if SleepState.shared.timer?.kind == .endOfChapter { cancelSleep() }
    state.episodeId = episode.id
    state.chapters = []
    state.jumping = false
    state.skipper = ChapterSkipper(skipped: ChapterSkipStore.skipped(for: episode.id))
    emitChapters()

    let id = episode.id
    let local = PodcastDownloader.shared.localFile(for: id)
    let address = episode.chaptersUrl
    guard local != nil || address != nil else { return }
    state.loading = Task { [weak self] in
      var file: [Chapter] = []
      if let local {
        file = await PodcastChapterSource.fromFile(local)
        if Task.isCancelled { return }
        // The file's chapters show at once; the feed's may take a moment.
        self?.setChapters(PodcastChapterSource.savingPictures(file, episodeId: id), for: id)
      }
      if let address {
        let feed = await PodcastChapterSource.fromFeed(address)
        if Task.isCancelled || feed.isEmpty { return }
        let chosen = ChapterList.choose(feed: feed, file: file)
        self?.setChapters(PodcastChapterSource.savingPictures(chosen, episodeId: id), for: id)
      }
    }
  }

  private func setChapters(_ chapters: [Chapter], for id: String) {
    let state = ChapterState.shared
    guard state.episodeId == id else { return }
    state.chapters = chapters
    // The place playback is at now was not reached by playing, so it is not skipped.
    state.skipper.seeked(to: position, in: chapters)
    emitChapters()
  }

  // MARK: Telling the app

  func chaptersInfo() -> [String: Any] {
    let state = ChapterState.shared
    let chapters: [[String: Any]] = state.chapters.map { chapter in
      var object: [String: Any] = [
        "start": chapter.start, "title": chapter.title,
        "skipped": state.skipper.skipped.contains(chapter.key),
      ]
      if let end = chapter.end { object["end"] = end }
      if let image = chapter.imageURL { object["imageUrl"] = image }
      if let url = chapter.url { object["url"] = url }
      return object
    }
    return ["episodeId": state.episodeId ?? "", "chapters": chapters]
  }

  func emitChapters() { sink?("onChaptersChange", chaptersInfo()) }

  /// The listener switched a chapter's skipping on or off.
  func setChapterSkipped(episodeId: String, start: Double, skipped: Bool) {
    let state = ChapterState.shared
    guard state.episodeId == episodeId, start.isFinite else { return }
    state.skipper.set(Int((start * 1000).rounded()), skipped: skipped)
    ChapterSkipStore.save(state.skipper.skipped, for: episodeId)
    emitChapters()
  }

  // MARK: Moving between chapters

  // These four read `place`, not the clock: a seek on its way (a far scrub on a stream) is where
  // the listener already is, so two quick presses of next count as two, and the sleep timer's
  // chapter is the one the listener sees.

  /// Whether a chapter starts after the playhead (for the headphones' next button).
  var chapterAhead: Bool {
    ChapterRules.nextTarget(at: place, in: ChapterState.shared.chapters) != nil
  }

  func previousChapter() {
    let chapters = ChapterState.shared.chapters
    guard !chapters.isEmpty else { return }
    seek(to: ChapterRules.previousTarget(at: place, in: chapters))
  }

  /// Goes to the next chapter; false when there is none.
  @discardableResult
  func nextChapter() -> Bool {
    guard let target = ChapterRules.nextTarget(at: place, in: ChapterState.shared.chapters)
    else { return false }
    seek(to: target)
    return true
  }

  /// Where the chapter playing now ends, for the sleep timer.
  func currentChapterEnd() -> Double? {
    let chapters = ChapterState.shared.chapters
    guard let index = ChapterRules.current(at: place, in: chapters) else { return nil }
    return ChapterRules.end(of: index, in: chapters, duration: currentDuration)
  }

  // MARK: Skipping

  /// The playhead was moved by the listener, a lock screen button or the app.
  func chapterSeeked(to position: Double) {
    let state = ChapterState.shared
    state.skipper.seeked(to: position, in: state.chapters)
    sleepSeeked(to: position)
  }

  /// Called with every tick of the clock: jumps over a skipped chapter that playback reached.
  func chapterTick() {
    let state = ChapterState.shared
    guard wantsToPlay, !state.jumping, !state.chapters.isEmpty,
      let target = state.skipper.check(
        position: position, in: state.chapters, duration: currentDuration)
    else { return }
    state.jumping = true
    noteSaved(.chapters, audioSeconds: target - position)
    player.seek(
      to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      Task { @MainActor in
        ChapterState.shared.jumping = false
        // The jump may have landed on or just past an ad's start, where no marker will fire.
        self?.adSkipping.refresh()
        self?.publish()
      }
    }
    publish(positionOverride: target)
  }
}
