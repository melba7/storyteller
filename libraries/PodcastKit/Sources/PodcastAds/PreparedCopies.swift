// LOFI-FORK: which of the Mac's copies the phone takes and which it gives back (see FORK.md and
// docs/PLAN.md, milestone Y4). Plain values: the phone reads its list, its downloads and its player
// and acts on the answer. Foundation only.
import Foundation

public enum PreparedCopies {
  /// At most this many copies are taken in one run: the whole list of next episodes.
  public static let most = 12

  /// What the phone has of an episode's audio.
  public enum Download: Sendable, Equatable {
    case none
    /// Moving or waiting to move.
    case moving
    /// A file with this SHA-256.
    case downloaded(sha256: String)
  }

  /// One episode the Mac may have prepared.
  public struct Candidate: Sendable, Equatable {
    public var id: String
    /// Its place on the phone's list of next episodes, counted from 0, or nil when it is not there.
    public var listPlace: Int?
    public var download: Download
    /// The episode was started: its position and its ads stay on the file it was started on.
    public var started: Bool
    public var inPlayer: Bool
    /// The audio the phone has was taken from the Mac only for the list.
    public var copyForListOnly: Bool
    /// The copy the Mac's file lists for the episode, if any.
    public var listed: PreparedCopy?
    /// The episode is anywhere in the listener's whole list of next episodes, also past the places
    /// that are taken. A copy is given back only when this is false and `listPlace` is nil.
    public var stillListed: Bool

    public init(
      id: String, listPlace: Int? = nil, download: Download = .none, started: Bool = false,
      inPlayer: Bool = false, copyForListOnly: Bool = false, listed: PreparedCopy? = nil,
      stillListed: Bool = false
    ) {
      self.stillListed = stillListed
      self.id = id
      self.listPlace = listPlace
      self.download = download
      self.started = started
      self.inPlayer = inPlayer
      self.copyForListOnly = copyForListOnly
      self.listed = listed
    }
  }

  public struct Plan: Sendable, Equatable {
    /// Episodes whose listed copy is to be taken: the list's order first, then the others.
    public var take: [String]
    /// Episodes whose copy was taken only for the list and is to be given back.
    public var giveBack: [String]

    public init(take: [String] = [], giveBack: [String] = []) {
      self.take = take
      self.giveBack = giveBack
    }
  }

  /// What to do now. A listed copy is taken when the episode is on the list or has a download, was
  /// not started, is not in the player, is not moving right now, and does not have that very copy
  /// (the same SHA-256). A copy taken only for the list is given back once its episode is off the
  /// list, was not started and is not in the player. Nothing else is taken or given back. An
  /// episode that is given back is not taken in the same run, and one that is named twice counts
  /// once, at its first place. At most `most` are taken; giving back is not limited.
  public static func plan(_ candidates: [Candidate], most: Int = PreparedCopies.most) -> Plan {
    var seen = Set<String>()
    let once = candidates.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    var plan = Plan()
    plan.giveBack = once.filter(givesBack).map(\.id)
    let back = Set(plan.giveBack)
    let wanted = once.filter { !back.contains($0.id) && takes($0) }
    let onList = wanted.enumerated().filter { $0.element.listPlace != nil }
      .sorted { ($0.element.listPlace ?? 0, $0.offset) < ($1.element.listPlace ?? 0, $1.offset) }
      .map(\.element)
    let others = wanted.filter { $0.listPlace == nil }
    plan.take = Array((onList + others).prefix(max(0, most)).map(\.id))
    return plan
  }

  private static func takes(_ one: Candidate) -> Bool {
    guard let listed = one.listed, !one.started, !one.inPlayer else { return false }
    switch one.download {
    case .moving: return false
    case .none: return one.listPlace != nil
    case .downloaded(let have): return have.lowercased() != listed.sha256.lowercased()
    }
  }

  private static func givesBack(_ one: Candidate) -> Bool {
    guard one.copyForListOnly, one.listPlace == nil, !one.stillListed, !one.started, !one.inPlayer,
      case .downloaded = one.download
    else { return false }
    return true
  }
}
