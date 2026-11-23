// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The one finder guard of the app (PodcastAds' FinderGuard, kept in `Podcasts/finder-guard.json`).
// Before a new finder runs on an episode a mark goes to disk; when it returns the mark is cleared.
// A mark found at the next launch means the app died inside that finder, and the guard switches
// it off for that episode (a second time: everywhere, until the next build). FinderGuard's header
// lists the rules this file keeps:
//  1. The file is loaded and `recover()` runs once, in `init`, and the file is saved after it.
//  2. There is one instance behind one lock. Every change is saved before the lock is let go.
//  3. `begin` is saved before a finder runs; when the save throws, the finder does not run.
//  4. `end` is saved when the finder returns or throws (`hold` does it in a `defer`).
//  5. Swift cancellation does not happen when iOS suspends the app or takes the background time
//     back. So a finder runs only inside `hold`, which holds time with `performExpiringActivity`,
//     and the activity's expiry calls `endAll` (every live mark ended and saved) and raises the
//     stop flag the finder looks at, before the time goes back.
// It never runs on the main actor: `hold` blocks the calling thread until the work is done.
import Foundation
import PodcastAds

/// Raised when the time a finder holds runs out. The finder looks at it between its steps.
final class StopFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var raised = false

  var isStopped: Bool { lock.withLock { raised } }
  func stop() { lock.withLock { raised = true } }
}

/// The finders that began under one `hold`, and the flag that says time is up.
struct Held {
  /// The finders whose mark is on disk. A finder that is not here must not run.
  var finders: Set<String>
  let stop: StopFlag
}

/// The names of the new finders. Four are `ShowTuning`'s; the other two have no setting of their
/// own beyond the sorts and `joints`.
enum FinderNames {
  static let ownSound = ShowTuning.ownSound
  static let repeatSound = ShowTuning.repeatSound
  static let repeatWords = ShowTuning.repeatWords
  static let meaning = ShowTuning.meaning
  static let joints = "joints"
  /// The word model's middle band, which only asks (AdAsks).
  static let wordModel = "word-model"
  /// The finders a skip or a question can come from: their answers go to the guard.
  static let answerable: Set<String> = [
    ownSound, repeatSound, repeatWords, meaning, wordModel,
  ]
}

final class PodcastFinderGuard: @unchecked Sendable {
  static let shared = PodcastFinderGuard(url: defaultURL, appBuild: currentBuild)

  static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent(FinderGuard.fileName)
  }

  /// The app's version and build, so a new build starts the traps again.
  static var currentBuild: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "0"
    let build = info?["CFBundleVersion"] as? String ?? "0"
    return "\(short)-\(build)"
  }

  /// How long `hold` waits for iOS to grant the time before it gives up and does not run.
  var grantSeconds = 5.0

  private struct Mark: Hashable {
    var finder: String
    var episode: String
  }

  private let url: URL
  private let lock = NSLock()
  private var state: FinderGuard
  /// The marks written and not ended, each with the holds that wrote it (two holds of one finder
  /// on one episode share the mark, and it is cleared when the last of them ends), and the flags
  /// of the holds that are running.
  private var live: [Mark: Set<Int>] = [:]
  private var holds: [ObjectIdentifier: StopFlag] = [:]
  private var holders = 0

  init(url: URL, appBuild: String, now: Date = Date()) {
    self.url = url
    var loaded = FinderGuard.load(from: url, appBuild: appBuild)
    let traps = loaded.recover()
    state = loaded
    for trap in traps {
      PodcastTimeline.mark(
        trap.episode,
        "finder guard: \(trap.finder) was running when the app stopped, it is off for this episode"
          + (trap.offEverywhere ? " and everywhere until the next build" : ""))
    }
    // The recovered marks are gone from the file only once this save works.
    if !traps.isEmpty { save(now) }
  }

  // MARK: What a finder may do

  /// What the listener's answers and the traps allow `finder` on this episode. `.skip` also means
  /// "nothing known": the settings decide whether a finder skips or only asks.
  func mode(finder: String, show: String, episode: String, now: Date = Date()) -> FinderMode {
    lock.withLock { state.mode(finder: finder, show: show, episode: episode, now: now) }
  }

  // MARK: What the listener did

  func undone(finder: String, show: String, now: Date = Date()) {
    lock.withLock {
      state.undone(finder: finder, show: show, now: now)
      save(now)
    }
  }

  func denied(finder: String, show: String, now: Date = Date()) {
    lock.withLock {
      state.denied(finder: finder, show: show, now: now)
      save(now)
    }
  }

  func confirmed(finder: String, show: String, now: Date = Date()) {
    lock.withLock {
      state.confirmed(finder: finder, show: show, now: now)
      save(now)
    }
  }

  // MARK: Running a finder

  /// Waits for iOS to hold time for the app and, once it does, writes the marks of `finders` for
  /// this episode and runs `work` on this thread. The marks are ended and saved when `work`
  /// returns, before the time is given back. Nil, and `work` does not run, when iOS did not grant
  /// the time or no mark could be written. `work` gets the finders that have a mark (it must run
  /// no others) and the flag that says the time is up. No mark is on disk while the app waits: a
  /// suspension or a kill in that gap is no crash of a finder.
  func hold<T>(
    _ finders: [String], episode: String, reason: String? = nil, _ work: (Held) -> T
  ) -> T? {
    guard !finders.isEmpty else { return nil }
    let stop = StopFlag()
    let key = ObjectIdentifier(stop)
    let holder = lock.withLock { () -> Int in
      holds[key] = stop
      holders += 1
      return holders
    }
    defer { lock.withLock { holds[key] = nil } }
    let started = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let granted = Granted()
    let named = reason ?? "Finding ads: " + finders.joined(separator: ", ")
    ProcessInfo.processInfo.performExpiringActivity(withReason: named) { [self] expired in
      if expired {
        // The time is up: ask the finder to stop, and clear every mark before it is given back.
        expireAll()
        return
      }
      guard granted.take() else { return }
      started.signal()
      finished.wait()
    }
    guard started.wait(timeout: .now() + grantSeconds) == .success else {
      // The block may have begun just now: it is waiting, so let it go.
      if granted.cancel() { finished.signal() }
      return nil
    }
    // The time is held. The marks come now, and go before the time is given back (the defers
    // run in the opposite order of their writing).
    defer { finished.signal() }
    let marked = finders.filter { begin($0, episode: episode, holder: holder) }
    defer { for finder in marked { end(finder, episode: episode, holder: holder) } }
    guard !marked.isEmpty else { return nil }
    return work(Held(finders: Set(marked), stop: stop))
  }

  /// Writes a mark and saves it. False, with no mark left in memory, when the save throws.
  func begin(_ finder: String, episode: String, holder: Int = 0, now: Date = Date()) -> Bool {
    lock.withLock {
      let mark = Mark(finder: finder, episode: episode)
      if live[mark] == nil {
        state.begin(finder: finder, episode: episode)
        do {
          try state.save(to: url, now: now)
        } catch {
          state.end(finder: finder, episode: episode)
          return false
        }
      }
      live[mark, default: []].insert(holder)
      return true
    }
  }

  /// Takes one hold's share of a mark. The mark is cleared and saved when no hold keeps it;
  /// nothing is written for a hold whose mark was cleared already (`expireAll`).
  func end(_ finder: String, episode: String, holder: Int = 0, now: Date = Date()) {
    lock.withLock {
      let mark = Mark(finder: finder, episode: episode)
      guard var keeping = live[mark], keeping.remove(holder) != nil else { return }
      if keeping.isEmpty {
        live[mark] = nil
        state.end(finder: finder, episode: episode)
        save(now)
      } else {
        live[mark] = keeping
      }
    }
  }

  /// Ends every live mark and saves once. Called when the time a finder holds expires.
  func endAll(now: Date = Date()) {
    lock.withLock {
      guard !live.isEmpty else { return }
      for mark in live.keys { state.end(finder: mark.finder, episode: mark.episode) }
      live = [:]
      save(now)
    }
  }

  /// The activity's time is up: every stop flag is raised and every live mark is ended and saved,
  /// before the time goes back. Called by the activity of `hold` and by a background task's
  /// expiration handler (an app that is killed with a mark on disk looks like a crash).
  func expireAll() {
    raiseStops()
    endAll()
  }

  /// The number of marks that are live now, for the harness.
  var liveMarks: Int { lock.withLock { live.count } }

  /// The same for one episode.
  func liveMarks(episode: String) -> Int {
    lock.withLock { live.keys.filter { $0.episode == episode }.count }
  }

  private func raiseStops() {
    let flags = lock.withLock { Array(holds.values) }
    for flag in flags { flag.stop() }
  }

  /// The caller holds the lock.
  private func save(_ now: Date) {
    do {
      try state.save(to: url, now: now)
    } catch {
      NSLog("Podcasts: the finder guard could not be saved: \(error)")
    }
  }
}

/// Whether the activity that `hold` asked iOS for may go on: it may not once `hold` gave up.
private final class Granted: @unchecked Sendable {
  private let lock = NSLock()
  private var begun = false
  private var cancelled = false

  /// True once, as long as `cancel` was not called first.
  func take() -> Bool {
    lock.withLock {
      guard !cancelled, !begun else { return false }
      begun = true
      return true
    }
  }

  /// Gives up. True when the activity had begun anyway (it is waiting and must be let go).
  func cancel() -> Bool {
    lock.withLock {
      cancelled = true
      return begun
    }
  }
}
