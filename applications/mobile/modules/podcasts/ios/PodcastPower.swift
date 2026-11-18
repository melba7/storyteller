// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the phone's power is now, for the background turns of the transcriber and the ad
// finder. The rule is PodcastAds' BackgroundPower: on the charger, or with at least 30%
// battery and Low Power Mode off.

import PodcastAds
import UIKit

enum PodcastPower {
  /// Turns the battery readings on; iOS gives none before that. Call on the main thread.
  @MainActor static func startWatching() {
    UIDevice.current.isBatteryMonitoringEnabled = true
  }

  @MainActor static func mayRunInBackground() -> Bool {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let charging = device.batteryState == .charging || device.batteryState == .full
    // A level of -1 means iOS does not know it.
    let level: Double? = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
    return BackgroundPower.mayRun(
      charging: charging, batteryLevel: level,
      lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
  }
}
