// LOFI-FORK: the phone's measuring diary: a line for every play that starts and a line for every
// finished transcription (see FORK.md and AdDiary.swift).
//
// It measures how often an episode is ready when the listener plays it, and how fast the phone
// transcribes, so the stream replay can use real numbers (`podcast-teach score --stream
// --speech N`, and `teach_pace.py` on the Mac, which reads these lines). A line is an ordinary
// diary line (`AdDiary.line`) with its own file, `play-diary.jsonl`, so the ad diary's 500 lines
// never push it out. It holds no words of the episode. Foundation only.
import Foundation

public enum PlayDiary {
  /// The diary's file name, beside the skip log and the ad diary.
  public static let fileName = "play-diary.jsonl"
  /// The most lines the file keeps. The oldest go first. A few months of listening.
  public static let maxLines = 2000

  /// How an episode stood when its play started.
  public enum Start: Equatable, Sendable {
    /// Its ads were found for the whole episode: the finished file is known before play.
    case ready
    /// Downloaded, but the ads were not finished: the transcript was made to this many seconds.
    case partly(transcriptTo: Double)
    /// Played as a stream: nothing was known about it.
    case stream
  }

  /// How an episode stood: a stream is a stream whatever is on the disk for it, a downloaded
  /// episode is ready only with a finished ads file.
  public static func start(
    isStream: Bool, hasFinishedAds: Bool, transcriptReached: Double
  ) -> Start {
    if isStream { return .stream }
    return hasFinishedAds ? .ready : .partly(transcriptTo: transcriptReached)
  }

  /// The diary line of a play that started: "play: ready", "play: partly, transcript to 240 s" or
  /// "play: stream".
  public static func line(at time: Double, episodeId: String, start: Start) -> String {
    let what: String
    switch start {
    case .ready: what = "play: ready"
    case .partly(let reached): what = "play: partly, transcript to \(whole(reached)) s"
    case .stream: what = "play: stream"
    }
    return AdDiary.line(at: time, episodeId: episodeId, what: what)
  }

  /// The diary line of a transcription that finished: "3600 s of audio in 214.3 s, front". `work`
  /// is the seconds it took. Empty when there is no audio or no time to count (nothing to say).
  public static func line(
    at time: Double, episodeId: String, audio: Double, work: Double, inBackground: Bool
  ) -> String {
    guard audio.isFinite, work.isFinite, audio > 0, work > 0 else { return "" }
    let place = inBackground ? "background" : "front"
    return AdDiary.line(
      at: time, episodeId: episodeId,
      what: "\(whole(audio)) s of audio in \(String(format: "%.1f", work)) s, \(place)")
  }

  /// The text of the file with `line` added at the end and the newest `maxLines` kept. Unlike the
  /// ad diary, a line that repeats the last one is kept: it is another play.
  public static func appending(_ line: String, to text: String) -> String {
    line.isEmpty ? AdDiary.trimmed(text, maxLines: maxLines)
      : AdDiary.trimmed(text + "\n" + line, maxLines: maxLines)
  }

  private static func whole(_ seconds: Double) -> Int {
    // Capped, because a feed can claim any duration and Int(...) stops the app above 9.2e18.
    seconds.isFinite ? Int(min(max(0, seconds), 1e9).rounded()) : 0
  }
}
