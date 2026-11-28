// LOFI-FORK: which new rows the scorecard gets, and the plain notes about the ones it leaves out
// (see FORK.md and AdScoreLayer.swift). Foundation only.
import Foundation
import PodcastTranscripts

/// What the caller of `AdScoreCommand` can add. PodcastAds cannot see the audio code or Apple's
/// sentence embedding, so the `podcast-teach` tool hands them in; with the defaults the rows that
/// need them are left out, and the notes say so.
public struct ScoreExtras: Sendable {
  /// The sound finders, made once for a run (they learn across episodes in boxes of their own).
  /// It gets the teaching folder (for the Mac's `ad-sounds.json`) and the time the run starts.
  /// Nil: this build has no audio code.
  public var sounds: @Sendable (URL, Date) -> ScoreSoundKit?
  /// The embedder for a meaning model, or nil when this Mac has none (Linux, or no English
  /// sentence embedding of the revision the model was trained on).
  public var embedder: @Sendable (AdMeaningModel) -> LineEmbedder?

  public init(
    sounds: @escaping @Sendable (URL, Date) -> ScoreSoundKit? = { _, _ in nil },
    embedder: @escaping @Sendable (AdMeaningModel) -> LineEmbedder? = { _ in nil }
  ) {
    self.sounds = sounds
    self.embedder = embedder
  }
}

/// The ads the word rules and the word model give for a whole episode, before any join. They tell
/// the joint rows (which only look at a whole episode) which ads with no source may be pulled back
/// to a joint (`JointPull`).
public typealias ScoreWords = @Sendable (AdScoreInput) -> [FoundAd]

/// The rows to add after the detectors, in the round's order, and what to say about the rest.
struct ScorePlan {
  var layers: [AdScoreLayer] = []
  /// Plain sentences about rows that are left out, printed under the scorecard's title.
  var notes: [String] = []
  var meaning: MeaningScoreNotes?
  /// The Mac's settings (or the built-in ones), for the question note.
  var tuning: ShowTuning?
  /// What the finder rows keep for the settings row, and the silent row that starts it.
  let finders = ScoreFinderAds()
  /// The rows that learn from the episodes before them: own sounds, repeated sounds, repeated words.
  var learners: [AdScoreLayer] = []
  /// The week's sound finder of the sound kit, when there is a kit and an MP3 file (`--week`).
  var weekScan: (@Sendable (URL, String) -> [ScoreSpan])?

  /// The order: the meaning model first (it skips by default, so a finder that only asks must not
  /// cut it), then own sounds, repeated sounds, repeated words, joints, joints in steady files too,
  /// and last the per-show settings. Each row stands on the one before it.
  static func make(
    folder: URL, episodes: [TeachingEpisode], audio: [String: URL], now: Date, extras: ScoreExtras,
    words: @escaping ScoreWords = { _ in [] }
  ) -> ScorePlan {
    var plan = ScorePlan()
    let finders = plan.finders
    let kit = plan.soundKit(folder: folder, episodes: episodes, audio: audio, now: now, extras: extras)
    let stash = ScoreEpisodeAds()
    plan.addMeaning(folder: folder, extras: extras)
    // With no MP3 file at all only the joints of `joints.json` can be used, so only the joint rows.
    if let kit, !audio.isEmpty {
      plan.layers.append(SoundScoreLayers.ownSounds(kit.ownSounds, finders: finders))
      plan.layers.append(SoundScoreLayers.repeatedSounds(kit.repeatedSounds, finders: finders))
      plan.weekScan = kit.weekSounds
    }
    plan.layers.append(WordScoreLayers.repeatedWords(now: now, finders: finders))
    let learning = [ScoreRows.ownSounds, ScoreRows.repeatedSounds, ScoreRows.repeatedWords]
    plan.learners = plan.layers.filter { learning.contains($0.name) }
    if let kit {
      plan.layers.append(SoundScoreLayers.joints(
          kit.snapJoints, stash: stash, cached: kit.cachedJoints, words: words))
      plan.layers.append(
        SoundScoreLayers.steadyJoints(
          kit.snapJoints, stash: stash, cached: kit.cachedJoints, words: words))
    }
    plan.addSettings(folder: folder, snap: kit?.snapJoints, cached: kit?.cachedJoints, words: words)
    return plan
  }

  /// The rows that learn, run over episodes that are not scored (the older episodes of the shelf's
  /// shows), in order, so the scored ones have something before them. Their rows are not kept.
  func teach(
    _ episodes: [TeachingEpisode], audio: [String: URL],
    base: (TeachingEpisode, Transcript) -> [FoundAd]
  ) {
    for episode in episodes {
      let input = AdScoreInput(
        episode: episode, transcript: episode.transcript, audio: audio[episode.id])
      var soFar = base(episode, episode.transcript)
      for layer in [finders.baseRow] + learners { soFar = layer.apply(input, soFar: soFar) }
    }
  }

  /// The sound finders when there is any audio to read, else nil and a note.
  private mutating func soundKit(
    folder: URL, episodes: [TeachingEpisode], audio: [String: URL], now: Date, extras: ScoreExtras
  ) -> ScoreSoundKit? {
    let rows = ScoreRows.needingAudio.joined(separator: ", ")
    guard let kit = extras.sounds(folder, now) else {
      notes.append("Rows left out: \(rows). This build of the tool has no audio code.")
      return nil
    }
    let kept = episodes.filter { kit.cachedJoints.has($0.id) }.count
    if kept > 0 {
      return cachedKit(kit, episodes: episodes, audio: audio, kept: kept)
    }
    let without = episodes.filter { audio[$0.id] == nil }.map(\.id)
    guard without.count < episodes.count else {
      notes.append(
        "No episode has an MP3 file in the teaching folder, so the rows that need audio are left out: \(rows).")
      return nil
    }
    if !without.isEmpty {
      notes.append(
        "\(without.count) of \(episodes.count) episodes have no MP3 file (\(Self.named(without))), so the rows that need audio leave them out.")
    }
    return kit
  }

  /// The ids as one phrase: the first five, then how many more.
  private static func named(_ ids: [String]) -> String {
    let more = ids.count > 5 ? " and \(ids.count - 5) more" : ""
    return ids.prefix(5).joined(separator: ", ") + more
  }

  /// The kit when `joints.json` holds the joints of `kept` of the episodes: an episode is out of
  /// the joint rows only when it has neither. The rows that read the audio need the MP3 files.
  private mutating func cachedKit(
    _ kit: ScoreSoundKit, episodes: [TeachingEpisode], audio: [String: URL], kept: Int
  ) -> ScoreSoundKit {
    let cache = "the joints in joints.json"
    if audio.isEmpty {
      let rows = [ScoreRows.ownSounds, ScoreRows.repeatedSounds].joined(separator: ", ")
      notes.append(
        "No episode has an MP3 file in the teaching folder, so the rows that need audio are left out: \(rows). The joints rows use \(cache), which holds \(kept) of \(episodes.count) episodes.")
    } else {
      let without = episodes.filter { audio[$0.id] == nil }.map(\.id)
      if !without.isEmpty {
        let neither = episodes.filter { audio[$0.id] == nil && !kit.cachedJoints.has($0.id) }.count
        notes.append(
          "\(without.count) of \(episodes.count) episodes have no MP3 file (\(Self.named(without))), so the rows that need audio leave them out; \(neither) of them have no joints in joints.json either, so the joints rows leave those out too.")
      }
    }
    return kit
  }

  private mutating func addMeaning(folder: URL, extras: ScoreExtras) {
    let url = folder.appendingPathComponent(AdMeaningModel.fileName)
    guard FileManager.default.fileExists(atPath: url.path) else {
      notes.append("The meaning model's row is left out: there is no \(AdMeaningModel.fileName) in the folder.")
      return
    }
    guard let model = AdMeaningModel.load(from: url) else {
      notes.append(
        "The meaning model's row is left out: \(AdMeaningModel.fileName) could not be read (or does not fit this phone code).")
      return
    }
    guard let embedder = extras.embedder(model) else {
      notes.append(
        "The meaning model's row is left out: it needs a Mac with Apple's English sentence embedding (revision \(model.revision)).")
      return
    }
    let seen = MeaningScoreNotes()
    meaning = seen
    layers.append(
      WordScoreLayers.meaning(model: model, embedder: embedder, notes: seen, finders: finders))
  }

  /// The settings row is always there: with no file (or one that cannot be read) it holds the
  /// built-in settings, which is what the phone does, so the run's total is the phone's.
  private mutating func addSettings(
    folder: URL, snap: (@Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan])?,
    cached: ScoreCachedJoints?, words: @escaping ScoreWords
  ) {
    let url = folder.appendingPathComponent(ShowTuning.fileName)
    var chosen = ShowTuning()
    if !FileManager.default.fileExists(atPath: url.path) {
      notes.append(
        "There is no \(ShowTuning.fileName) in the folder, so the per-show settings row uses the built-in settings.")
    } else if let data = try? Data(contentsOf: url) {
      chosen = ShowTuning(data: data)
    } else {
      notes.append(
        "\(ShowTuning.fileName) could not be read, so the per-show settings row uses the built-in settings.")
    }
    tuning = chosen
    layers.append(SettingsScoreLayer.perShowSettings(
        tuning: chosen, finders: finders, snap: snap, cached: cached ?? ScoreCachedJoints(),
        words: words))
  }

  /// What the meaning row noticed, as plain sentences.
  func meaningLines() -> [String] {
    guard let meaning else { return [] }
    var lines: [String] = []
    if meaning.episodes > 0 {
      let speed = meaning.secondsPerLine.map { String(format: " (about %.0f ms a line)", $0 * 1000) } ?? ""
      lines.append("The meaning model read \(meaning.episodes) episode\(meaning.episodes == 1 ? "" : "s")\(speed).")
    }
    for reason in meaning.offReasons { lines.append("The meaning model was off for an episode: \(reason)") }
    return lines
  }
}
