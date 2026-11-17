// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import Foundation
import Network

/// Whether the phone is on Wi-Fi right now (or any network that is not expensive, such as
/// Ethernet), by the same test the downloader uses to keep a download off mobile data.
final class PodcastNetwork: @unchecked Sendable {
  static let shared = PodcastNetwork()

  private let lock = NSLock()
  private var path: NWPath?
  private let monitor = NWPathMonitor()

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      self.lock.withLock { self.path = path }
    }
    monitor.start(queue: DispatchQueue(label: "PodcastNetwork"))
  }

  /// False until the monitor has reported once, which it does within moments of starting.
  var onWiFi: Bool {
    lock.withLock {
      guard let path else { return false }
      return path.status == .satisfied && !path.isExpensive
    }
  }
}
