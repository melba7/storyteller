import Foundation

/// Turns the count of scored entries into a progress line with an estimated finish
/// time, for the log of a long scoring run.
///
/// A run has two parts: the main pass (one request at a time, in order) and then the
/// in-between checks at the changes of scene (several at once, at most `probeBudget`
/// of them, usually fewer). The estimate for the checks is therefore an upper bound.
public final class ScoringProgress: @unchecked Sendable {
    public let planned: Int
    public let alreadyScored: Int
    public let probeBudget: Int
    public let concurrency: Int
    public let every: Int
    public let timeZone: TimeZone

    private let lock = NSLock()
    private let started: Date
    private var mainPassEnded: Date?
    private var failed = 0
    /// Failures of the main pass: those scenes never arrive as entries.
    private var failedScenes = 0

    /// - Parameters:
    ///   - planned: the scenes of the main pass, counting the ones already there.
    ///   - alreadyScored: scenes a stopped run left in the file.
    ///   - probeBudget: the most in-between checks this run may still make.
    public init(
        planned: Int,
        alreadyScored: Int,
        probeBudget: Int,
        concurrency: Int = 4,
        every: Int = 10,
        started: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        self.planned = planned
        self.alreadyScored = min(alreadyScored, planned)
        self.probeBudget = max(0, probeBudget)
        self.concurrency = max(1, concurrency)
        self.every = max(1, every)
        self.started = started
        self.timeZone = timeZone
    }

    /// Scenes the main pass has to score in this run.
    public var toScore: Int { planned - alreadyScored }

    /// Counts a request that failed, and returns a line for the first failure and for
    /// every tenth after it, so a run that has hit a usage limit shows it at once.
    public func failure(_ reason: String) -> String? {
        lock.lock()
        failed += 1
        if mainPassEnded == nil, failedScenes < toScore { failedScenes += 1 }
        let count = failed
        lock.unlock()
        guard count == 1 || count % 10 == 0 else { return nil }
        let short = reason.count > 160 ? String(reason.prefix(160)) + "…" : reason
        return "  \(count) failed so far (they are skipped; run again without --rescore to retry them): \(short)"
    }

    /// The line for the entry that made `added` (scenes first, then checks), or nil
    /// when this entry is not due one. `dollars` is the spend so far, when known.
    public func line(added: Int, dollars: Double? = nil, now: Date = Date()) -> String? {
        lock.lock()
        defer { lock.unlock() }
        // Failed scenes never arrive, so the main pass is over once the entries and its
        // failures together cover it and one more entry comes in.
        let scenesScored = toScore - failedScenes
        let inMainPass = mainPassEnded == nil && added <= scenesScored
        if !inMainPass, mainPassEnded == nil { mainPassEnded = now }
        let spent = dollars.map { String(format: ", about $%.2f so far", $0) } ?? ""
        let failures = failed > 0 ? ", \(failed) failed" : ""
        if inMainPass {
            guard added % every == 0 || added == scenesScored else { return nil }
            let elapsed = now.timeIntervalSince(started)
            let each = elapsed / Double(max(1, added))
            let left = Double(max(0, scenesScored - added)) * each
            let checks = Double(probeBudget) * each / Double(concurrency)
            let done = alreadyScored + added
            var text = "  \(done) of \(planned) scenes (\(Self.percent(done, of: planned)))\(failures)\(spent)"
            text += "; main pass done in about \(Self.minutes(left)) (\(clock(now.addingTimeInterval(left))))"
            if probeBudget > 0 {
                text += ", then up to \(probeBudget) in-between checks: all done by about \(clock(now.addingTimeInterval(left + checks))) at the latest"
            }
            return text
        }
        let checksDone = max(0, added - scenesScored)
        guard checksDone % every == 0 || checksDone == 1 else { return nil }
        let since = now.timeIntervalSince(mainPassEnded ?? now)
        let missing = failedScenes > 0 ? "main pass over (\(failedScenes) scenes failed)" : "all \(planned) scenes done"
        var text = "  \(missing); in-between check \(checksDone) of at most \(probeBudget)\(failures)\(spent)"
        if checksDone >= every, since > 0 {
            let left = Double(max(0, probeBudget - checksDone)) * since / Double(checksDone)
            text += "; done in at most \(Self.minutes(left)) (\(clock(now.addingTimeInterval(left))))"
        }
        return text
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        whole > 0 ? "\(Int((Double(part) / Double(whole) * 100).rounded()))%" : "100%"
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let whole = Int((seconds / 60).rounded())
        if whole < 1 { return "under a minute" }
        if whole < 90 { return "\(whole) min" }
        return String(format: "%.1f hours", seconds / 3600)
    }

    func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
