import Foundation
import LofiDirector

/// A handle to a scheduled action.
public protocol LofiCancellable: AnyObject {
    func cancel()
}

/// Where the player runs: a clock plus timers and a way to hop onto its context.
///
/// ``LofiScorePlayer`` touches its state only inside actions run by its scheduler, so the
/// scheduler is also its lock. In the app that is ``DispatchScheduler`` (one serial queue);
/// in tests it is ``ManualScheduler``, where time only moves when the test says so.
public protocol LofiScheduler: LofiClock {
    /// Runs `action` after `delay` seconds, on the scheduler's context.
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> LofiCancellable

    /// Runs `action` every `interval` seconds until cancelled. Keep the handle and cancel it
    /// explicitly; a ``DispatchScheduler`` timer also stops when its handle is released.
    func scheduleRepeating(every interval: TimeInterval, _ action: @escaping () -> Void) -> LofiCancellable

    /// Runs `action` on the scheduler's context: right away if already there, otherwise soon.
    func perform(_ action: @escaping () -> Void)
}

/// Runs everything on one serial dispatch queue, with wall-clock time.
public final class DispatchScheduler: LofiScheduler, @unchecked Sendable {
    public let queue: DispatchQueue
    private let clock = SystemClock()
    private let key = DispatchSpecificKey<UInt8>()

    public init(label: String = "LofiScoreKit.player", qos: DispatchQoS = .userInitiated) {
        queue = DispatchQueue(label: label, qos: qos)
        queue.setSpecific(key: key, value: 1)
    }

    /// Runs on an existing serial queue, such as `.main` for code that drives the UI.
    public init(queue: DispatchQueue) {
        self.queue = queue
        queue.setSpecific(key: key, value: 1)
    }

    public var now: TimeInterval { clock.now }

    /// True when called from this scheduler's queue.
    public var isCurrent: Bool { DispatchQueue.getSpecific(key: key) != nil }

    public func perform(_ action: @escaping () -> Void) {
        if isCurrent {
            action()
        } else {
            queue.async { action() }
        }
    }

    public func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> LofiCancellable {
        let item = DispatchWorkItem { action() }
        queue.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return WorkItemHandle(item)
    }

    public func scheduleRepeating(every interval: TimeInterval, _ action: @escaping () -> Void) -> LofiCancellable {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
        source.setEventHandler { action() }
        source.resume()
        return TimerHandle(source)
    }

    private final class WorkItemHandle: LofiCancellable {
        private let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    private final class TimerHandle: LofiCancellable {
        private let source: DispatchSourceTimer
        init(_ source: DispatchSourceTimer) { self.source = source }
        func cancel() { source.cancel() }
        deinit { source.cancel() }
    }
}

/// A scheduler whose time only moves when ``advance(by:)`` or ``advance(to:)`` is called.
/// Actions run in time order (ties in the order they were scheduled), synchronously.
public final class ManualScheduler: LofiScheduler {
    public private(set) var now: TimeInterval

    private var entries: [Entry] = []
    private var sequence = 0

    public init(now: TimeInterval = 0) {
        self.now = now
    }

    public func perform(_ action: @escaping () -> Void) {
        action()
    }

    public func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> LofiCancellable {
        let entry = Entry(fireAt: now + max(0, delay), interval: nil, sequence: nextSequence(), action: action)
        insert(entry)
        return entry
    }

    public func scheduleRepeating(every interval: TimeInterval, _ action: @escaping () -> Void) -> LofiCancellable {
        precondition(interval > 0, "a repeating interval must be positive")
        let entry = Entry(fireAt: now + interval, interval: interval, sequence: nextSequence(), action: action)
        insert(entry)
        return entry
    }

    /// Number of actions waiting to run.
    public var pendingCount: Int {
        entries.filter { !$0.isCancelled }.count
    }

    public func advance(by seconds: TimeInterval) {
        advance(to: now + seconds)
    }

    /// Moves time to `time`, running every action that falls due on the way, in order.
    public func advance(to time: TimeInterval) {
        precondition(time >= now - 1e-12, "ManualScheduler cannot go backwards")
        while true {
            entries.removeAll { $0.isCancelled }
            guard let entry = entries.first, entry.fireAt <= time else { break }
            entries.removeFirst()
            now = max(now, entry.fireAt)
            if let interval = entry.interval {
                entry.fireAt += interval
                entry.sequence = nextSequence()
                insert(entry)
            }
            entry.action()
        }
        now = max(now, time)
    }

    private func nextSequence() -> Int {
        sequence += 1
        return sequence
    }

    private func insert(_ entry: Entry) {
        let index = entries.firstIndex { ($0.fireAt, $0.sequence) > (entry.fireAt, entry.sequence) } ?? entries.endIndex
        entries.insert(entry, at: index)
    }

    private final class Entry: LofiCancellable {
        var fireAt: TimeInterval
        let interval: TimeInterval?
        var sequence: Int
        let action: () -> Void
        private(set) var isCancelled = false

        init(fireAt: TimeInterval, interval: TimeInterval?, sequence: Int, action: @escaping () -> Void) {
            self.fireAt = fireAt
            self.interval = interval
            self.sequence = sequence
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }
}
