// LOFI-FORK: how fast the phone is assumed to be when the scorecard replays a stream (see FORK.md
// and StreamReplay.swift). Foundation only.
import Foundation

/// The speeds the stream replay assumes. They are guesses, not measurements, and the report
/// prints them so nobody mistakes the replay for a measurement of a real phone.
public struct StreamPace: Equatable, Sendable {
  public var name: String
  /// Seconds from the tap to the first byte.
  public var connect = 1.0
  /// Seconds of audio that arrive on disk in one second.
  public var download = 40.0
  /// Seconds of audio the phone transcribes in one second.
  public var speech = 12.0
  /// Seconds each step costs besides the transcribing.
  public var stepOverhead = 0.5
  /// Seconds Apple's model needs for a minute of the head read so far (the phone asks it about
  /// the whole head each time), and the least it ever needs.
  public var modelPerMinute = 2.0
  public var modelFloor = 2.0
  /// Seconds of silence a jump costs.
  public var seek = 1.0
  /// Whether the head scan waits for Apple's model at the steps that ask it, as on a phone with
  /// Apple Intelligence on. The model's answers are used only in the row that has them.
  public var waitsForModel = true
  /// The finished file is known before the listener taps play: the times do not matter.
  public var isInstant = false

  /// A phone on a good connection with nothing else to do.
  public static let standard = StreamPace(name: "standard")

  /// The same player with the finished file known at the start, to compare a stream with.
  public static let instant: StreamPace = {
    var pace = StreamPace(name: "instant")
    pace.isInstant = true
    return pace
  }()

  /// This pace with another speech speed (seconds of audio transcribed per second).
  public func withSpeech(_ speech: Double) -> StreamPace {
    var pace = self
    pace.speech = speech
    return pace
  }

  /// The standard pace with the speech speed the phone measured (`teach_pace.py` reads it from
  /// the phone's diary), for `podcast-teach score --stream --speech N`.
  public static func measured(speech: Double) -> StreamPace {
    var pace = standard
    pace.name = "measured"
    pace.speech = speech
    return pace
  }

  /// A weak connection and a busy phone: the audio arrives and is read much more slowly.
  public static let slow: StreamPace = {
    var pace = StreamPace(name: "slow")
    pace.download = 4.0
    pace.speech = 5.0
    return pace
  }()

  public init(name: String) { self.name = name }

  /// The seconds the model needs for `audio` seconds of audio.
  public func modelSeconds(forAudio audio: Double) -> Double {
    max(modelFloor, modelPerMinute * max(0, audio) / 60)
  }

  /// The pace in plain words, for the report.
  public var summary: String {
    func number(_ value: Double) -> String { String(format: "%g", value) }
    return
      "\(name): \(number(connect)) s to the first byte, \(number(download)) s of audio downloaded and \(number(speech)) s transcribed per second, \(number(stepOverhead)) s extra per step, the model \(number(modelPerMinute)) s per minute of the head read so far (at least \(number(modelFloor)) s), \(waitsForModel ? "the head scan waits for it" : "the head scan does not wait for it"), a jump costs \(number(seek)) s"
  }
}
