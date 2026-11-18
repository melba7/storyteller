// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// A failed full ad pass is asked again while the app runs, not only when it comes to the front:
// after a minute, then five, then fifteen (PodcastAds' PrepRetry). After that it waits for the
// app to come to the front again.

import Foundation
import PodcastAds

extension PodcastAdFinder {
  /// Clears the episode's failure after the next wait, so the next scan queues it again.
  func retryLater(_ id: String) {
    let delay = lock.withLock { () -> TimeInterval? in
      let count = (failureCounts[id] ?? 0) + 1
      failureCounts[id] = count
      return PrepRetry.delay(afterFailures: count)
    }
    guard let delay else { return }
    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
      let stillFailed = lock.withLock { () -> Bool in
        guard failures[id] != nil else { return false }
        failures[id] = nil
        return true
      }
      if stillFailed { scan() }
    }
  }

  /// The words for the listener for an error.
  static func reason(for error: Error) -> String {
    "Finding ads stopped: \(error.localizedDescription)"
  }
}
