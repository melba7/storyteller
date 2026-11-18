// LOFI-FORK: a time limit around one async step (see FORK.md). Foundation only.
import Foundation

/// Runs `operation` and gives its result, or throws `TranscriptError.failed(message)` when it
/// has not finished after `seconds`. The operation is cancelled at the limit, and the answer does
/// not wait for an operation that ignores the cancel, so a call that never returns cannot hold
/// the caller for ever. The caller's own cancel is passed on to the operation.
public func withTimeLimit<T: Sendable>(
  seconds: Double, message: String, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  let race = TimeLimitRace<T>()
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      race.start(continuation)
      race.work = Task {
        do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) }
      }
      race.timer = Task {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        race.finish(.failure(TranscriptError.failed(message)))
      }
    }
  } onCancel: {
    race.finish(.failure(CancellationError()))
  }
}

private final class TimeLimitRace<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?
  private var early: Result<T, Error>?
  private var done = false
  var work: Task<Void, Never>?
  var timer: Task<Void, Never>?

  func start(_ continuation: CheckedContinuation<T, Error>) {
    let ready = lock.withLock { () -> Result<T, Error>? in
      if let early { return early }
      self.continuation = continuation
      return nil
    }
    if let ready { continuation.resume(with: ready) }
  }

  /// The first result wins; the other task is cancelled.
  func finish(_ result: Result<T, Error>) {
    let (go, waiting) = lock.withLock { () -> (Bool, CheckedContinuation<T, Error>?) in
      guard !done else { return (false, nil) }
      done = true
      if continuation == nil { early = result }
      return (true, continuation)
    }
    guard go else { return }
    work?.cancel()
    timer?.cancel()
    waiting?.resume(with: result)
  }
}
