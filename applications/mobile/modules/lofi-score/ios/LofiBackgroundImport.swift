// LOFI-FORK: finishing a sounds folder import after the app has closed (see FORK.md).
//
// When the app leaves the screen with a copy unfinished, it asks iOS for a background
// processing task. iOS picks the time (often overnight on the charger) and wakes the app,
// which carries on copying from where it stopped. iCloud keeps downloading the files on
// its own in the meantime: the import asked for all of them at the start.

import BackgroundTasks
import ExpoModulesCore
import LofiScoreHost
import UIKit

enum LofiBackgroundImport {
  /// Listed in Info.plist's BGTaskSchedulerPermittedIdentifiers by fork.config.ts.
  static var identifier: String {
    (Bundle.main.bundleIdentifier ?? "storyteller-lofi") + ".soundsImport"
  }

  /// Asks iOS for background time to finish the copy. Replaces an earlier request.
  static func schedule() {
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("LofiScore: could not ask for background time to finish the import: \(error)")
    }
  }

  static func run(_ task: BGTask) {
    let host = LofiScoreRuntime.shared.host
    Task {
      let done = await host.finishSyncInBackground()
      if !done { schedule() }
      task.setTaskCompleted(success: done)
    }
    task.expirationHandler = {
      // The copy saves its place and stops after the current file; the task above then
      // asks for another turn.
      host.stopSync()
    }
  }
}

/// Registers the background task while the app launches, as iOS requires.
public final class LofiScoreAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: LofiBackgroundImport.identifier, using: nil) { task in
      LofiBackgroundImport.run(task)
    }
    return true
  }
}
