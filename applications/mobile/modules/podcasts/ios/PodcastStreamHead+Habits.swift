// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the Mac taught about how the shows start (ShowHabits), with the phone's own notes of how
// they start (PodcastShowStarts) for the shows the Mac does not know that open with an ad, as the
// main actor may ask for it. PodcastTeaching reads its files the first time it is asked, and the
// player's Play (the short wait in PodcastPlayer+StartHold.swift) runs on the main actor, which
// must never read a file. So this keeps a copy of the habits, filled from a background task each
// time a stream's head is made, long before Play can be pressed. Until it is filled (or when
// nothing was taught and nothing was seen) it says nothing is known, which is the usual wait.
import Foundation
import PodcastAds

final class PodcastHabits: @unchecked Sendable {
  static let shared = PodcastHabits()

  private let lock = NSLock()
  private var habits = ShowHabits()

  private init() {}

  /// The habits read so far. Never reads a file, so any thread may ask.
  var current: ShowHabits { lock.withLock { habits } }

  /// Reads the habits (and so the teaching files and the phone's own notes, the first time) on a
  /// background task, and keeps them. Called again for each stream, so a file installed since, or
  /// what the last scan saw, is picked up.
  func warm() {
    Task.detached(priority: .utility) { [self] in
      PodcastShowStarts.shared.warm()
      let read = merged()
      lock.withLock { habits = read }
    }
  }

  /// What the Mac taught, with the phone's own notes for the shows the Mac has no entry for that
  /// opened with an ad (a show that never did is left to PodcastShowStarts.startsClean). It reads
  /// files, so only a background task calls it, never the main actor.
  func merged() -> ShowHabits {
    PodcastTeaching.shared.files.habits.merged(with: PodcastShowStarts.shared.habits())
  }
}
