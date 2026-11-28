// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import Foundation
import Network
import PodcastDownloads

/// Whether the phone is on Wi-Fi right now (or any network that is not expensive, such as
/// Ethernet), by the same test the downloader uses to keep a download off mobile data.
final class PodcastNetwork: @unchecked Sendable {
  static let shared = PodcastNetwork()

  private let lock = NSLock()
  private var path: NWPath?
  /// Notices Wi-Fi coming back, so what waited for it is looked at again (PodcastDownloadAhead).
  private var watch = DownloadAhead.NetworkWatch()
  private let monitor = NWPathMonitor()

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      let returned = self.lock.withLock { () -> Bool in
        self.path = path
        return self.watch.reported(
          onWiFi: path.status == .satisfied && !path.isExpensive, lowData: path.isConstrained)
      }
      if returned { Task { @MainActor in PodcastDownloadAhead.shared.changed() } }
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

  /// Whether prepared copies may be fetched now: on Wi-Fi and not in Low Data Mode. The first
  /// report of the path monitor is waited for, for one second at most, so a run right after the
  /// launch is not skipped.
  func allowsCopies() async -> Bool {
    for _ in 0..<10 {
      if lock.withLock({ path != nil }) { break }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return onWiFi && !isConstrained
  }

  /// Whether the network is in Low Data Mode (the listener turned it on for this Wi-Fi network or
  /// for mobile data, to save data). True until the monitor has reported once, so nothing that
  /// keeps out of Low Data Mode starts before the network is known.
  var isConstrained: Bool {
    lock.withLock { path?.isConstrained ?? true }
  }
}
