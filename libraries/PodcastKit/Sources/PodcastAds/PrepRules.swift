// LOFI-FORK: the order and the rules for getting episodes ready (see FORK.md).
import Foundation

/// Where an episode is in being made ready (transcript, then ads).
public enum PrepState: Sendable, Equatable {
  case needsWork
  case done
  /// Failed for good, or not supported (a language the phone cannot transcribe).
  case failed
  case unsupported
}

public struct PrepCandidate: Sendable, Equatable {
  public var id: String
  /// When the download was filed: newer ones are worked on first.
  public var addedAt: Date
  public var state: PrepState

  public init(id: String, addedAt: Date, state: PrepState) {
    self.id = id
    self.addedAt = addedAt
    self.state = state
  }
}

/// Which episode is worked on next, for transcribing and for finding ads alike.
public enum PrepOrder {
  /// The episodes that need work, in order: the playing one, then Up Next in its order, then
  /// the other downloads, newest first. Settled episodes and unknown names are left out.
  public static func order(_ candidates: [PrepCandidate], playing: String?, upNext: [String]) -> [String] {
    let open = candidates.filter { $0.state == .needsWork }
    let openIds = Set(open.map(\.id))
    var result: [String] = []
    for id in [playing].compactMap({ $0 }) + upNext where openIds.contains(id) && !result.contains(id) {
      result.append(id)
    }
    let rest = open.filter { !result.contains($0.id) }.sorted {
      $0.addedAt != $1.addedAt ? $0.addedAt > $1.addedAt : $0.id < $1.id
    }
    return result + rest.map(\.id)
  }

  public static func next(_ candidates: [PrepCandidate], playing: String?, upNext: [String]) -> String? {
    order(candidates, playing: playing, upNext: upNext).first
  }
}

/// What waits to be done for an episode: its head (the first minutes, so a pre-roll is found
/// before the rest) and then its rest.
public struct PrepWork: Sendable, Equatable {
  public var id: String
  public var addedAt: Date
  public var headPending: Bool
  public var restPending: Bool

  public init(id: String, addedAt: Date, headPending: Bool, restPending: Bool) {
    self.id = id
    self.addedAt = addedAt
    self.headPending = headPending
    self.restPending = restPending
  }
}

public enum PrepStage: Sendable, Equatable {
  case head
  case rest
}

public struct PrepStep: Sendable, Equatable {
  public var id: String
  public var stage: PrepStage

  public init(id: String, stage: PrepStage) {
    self.id = id
    self.stage = stage
  }
}

public enum PrepRules {
  /// The head of an episode: its first three minutes, which is the first two transcript pieces
  /// (60 and 120 seconds), so a head is cut the same way as the first part of a whole run.
  public static let headSeconds = 180.0
}

extension PrepOrder {
  /// The next piece of work. The playing episode goes first, its head and then its rest, because
  /// the listener hears it now. Otherwise every waiting episode gets its head before any
  /// episode's rest, so the first ad of each is known when it is played: the heads follow
  /// `order` (Up Next, then the newest downloads), and so do the rests after them.
  public static func nextStep(_ works: [PrepWork], playing: String?, upNext: [String]) -> PrepStep? {
    let pending = works.filter { $0.headPending || $0.restPending }
    let candidates = pending.map { PrepCandidate(id: $0.id, addedAt: $0.addedAt, state: .needsWork) }
    let ordered = order(candidates, playing: playing, upNext: upNext)
    let byId = Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    if let playing, let work = byId[playing] {
      return PrepStep(id: playing, stage: work.headPending ? .head : .rest)
    }
    if let id = ordered.first(where: { byId[$0]?.headPending == true }) {
      return PrepStep(id: id, stage: .head)
    }
    return ordered.first.map { PrepStep(id: $0, stage: .rest) }
  }

  /// Whether the episode being worked on stops at its next piece to make way. A rest makes way
  /// for any other episode's head (the heads come first); a head makes way only for the playing
  /// episode. The same episode's own next stage never makes it stop.
  public static func shouldYield(working: PrepStep, next: PrepStep?, playing: String?) -> Bool {
    guard let next, next.id != working.id else { return false }
    if working.stage == .rest { return next.stage == .head || next.id == playing }
    return next.id == playing
  }
}

/// When the background turns may run.
public enum BackgroundPower {
  /// Below this charge a turn on the battery does not run.
  public static let minimumBattery = 0.30

  /// Neither background task asks iOS for the charger: `mayRun` decides when its turn starts.
  public static let requiresExternalPower = false

  /// On the charger, or with at least 30% battery and Low Power Mode off. An unknown level
  /// counts as not enough.
  public static func mayRun(charging: Bool, batteryLevel: Double?, lowPowerMode: Bool) -> Bool {
    if charging { return true }
    guard let batteryLevel, !lowPowerMode else { return false }
    return batteryLevel >= minimumBattery
  }
}

/// How long to wait before trying a failed ad pass again.
public enum PrepRetry {
  private static let delays: [TimeInterval] = [60, 300, 900]

  /// The wait after the given number of failures in a row, or nil to stop trying.
  public static func delay(afterFailures count: Int) -> TimeInterval? {
    guard count >= 1, count <= delays.count else { return nil }
    return delays[count - 1]
  }
}
