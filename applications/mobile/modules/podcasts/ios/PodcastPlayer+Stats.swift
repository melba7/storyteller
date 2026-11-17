// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The listening stats, counted in Swift so they count with the screen locked and no JavaScript.
// The values and rules are PodcastPlayback's ListeningStats and ListenClock. The stats are saved
// as `Podcasts/stats.json` in Application Support: at most every 30 seconds while playing, and
// when playback pauses or the app goes to the background, never on every tick.

import Foundation
import PodcastPlayback
import UIKit

final class StatsStore: @unchecked Sendable {
  static let shared = StatsStore()

  /// The key trimming used before it joined the stats file. Read once and folded in.
  private static let oldTrimKey = "podcasts.trim.savedSeconds"
  private static let saveEvery = 30.0

  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("stats.json")
  }

  private let lock = NSLock()
  private var stats: ListeningStats
  private var clock = ListenClock()
  private var dirty = false
  private var lastSave = ProcessInfo.processInfo.systemUptime
  /// What the last ad skip added, so Undo can take exactly that back.
  private var lastAdSkip = 0.0

  private init() {
    var loaded = ListeningStatsFile.load(from: Self.url)
    let defaults = UserDefaults.standard
    if defaults.object(forKey: Self.oldTrimKey) != nil {
      loaded.addSaved(.trim, defaults.double(forKey: Self.oldTrimKey))
      defaults.removeObject(forKey: Self.oldTrimKey)
      dirty = true
    }
    stats = loaded
    if dirty { saveLocked() }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
    ) { [weak self] _ in self?.flush() }
  }

  private func edit(_ change: (inout ListeningStats) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    change(&stats)
    dirty = true
  }

  // MARK: Counting

  /// The player's 0.5 s tick: adds the time listened (only while really playing) and what the
  /// speed saved, and saves if 30 seconds have passed.
  func tick(playing: Bool, rate: Double) {
    let now = ProcessInfo.processInfo.systemUptime
    lock.lock()
    let added = clock.tick(at: now, playing: playing, rate: rate)
    if added.listened > 0 {
      stats.addListened(added.listened, at: Date())
      stats.addSaved(.speed, added.bySpeed)
      dirty = true
    }
    if dirty, now - lastSave >= Self.saveEvery { saveLocked() }
    lock.unlock()
  }

  func addSaved(_ category: StatsCategory, _ seconds: Double) {
    if category == .ads { lock.lock(); lastAdSkip = seconds; lock.unlock() }
    edit { $0.addSaved(category, seconds) }
  }

  /// The listener undid the last ad skip.
  func undoAdSkip() {
    lock.lock()
    let seconds = lastAdSkip
    lastAdSkip = 0
    lock.unlock()
    edit { $0.removeSaved(.ads, seconds) }
  }

  var trimSeconds: Double {
    lock.lock()
    defer { lock.unlock() }
    return stats.savedByTrim
  }

  // MARK: Saving and the app

  /// Writes the stats now, if anything changed.
  func flush() {
    lock.lock()
    if dirty { saveLocked() }
    lock.unlock()
  }

  private func saveLocked() {
    do {
      try ListeningStatsFile.save(stats, to: Self.url)
      dirty = false
      lastSave = ProcessInfo.processInfo.systemUptime
    } catch {
      NSLog("Podcasts: the stats could not be saved: \(error)")
    }
  }

  func reset() {
    lock.lock()
    stats = ListeningStats()
    lastAdSkip = 0
    saveLocked()
    lock.unlock()
  }

  /// The stats for the app, as a plain object.
  func object() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return [
      "listened": stats.listened, "savedBySpeed": stats.savedBySpeed,
      "savedBySkipping": stats.savedBySkipping, "savedByTrim": stats.savedByTrim,
      "savedByAds": stats.savedByAds, "savedByChapters": stats.savedByChapters,
      "days": stats.days,
    ]
  }
}

@MainActor
extension PodcastPlayer {
  /// Called with every tick of the clock.
  func statsTick() {
    StatsStore.shared.tick(
      playing: player.timeControlStatus == .playing, rate: Double(player.rate))
  }

  /// Seconds of audio that were jumped over, as the time they would have taken at this speed.
  func noteSaved(_ category: StatsCategory, audioSeconds: Double) {
    StatsStore.shared.addSaved(category, audioSeconds / max(1, speed.value))
  }
}
