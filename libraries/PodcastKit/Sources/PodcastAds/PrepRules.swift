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
