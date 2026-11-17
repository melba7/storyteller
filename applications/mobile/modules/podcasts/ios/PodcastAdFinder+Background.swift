// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// When the app leaves the screen with ads still to find, it asks iOS for a background
// processing task (`<bundle id>.podcastAds`). Unlike the transcribing task, this one asks to
// run only on the charger. Running the model for an hour-long episode keeps the phone busy for
// a minute or more, which should not use the battery, and iOS limits how much of the model an
// app in the background may use, so a long, plugged-in turn at night suits it best. iOS picks
// the time and wakes the app. When it says the time is up, the piece being asked about is
// finished, then the task asks for another turn. Nothing is saved for a half-done episode, so
// the next turn starts that episode over.

import BackgroundTasks
import Foundation
import UIKit

extension PodcastAdFinder {
  /// Listed in Info.plist's BGTaskSchedulerPermittedIdentifiers by fork.config.ts.
  static var identifier: String {
    (Bundle.main.bundleIdentifier ?? "storyteller-lofi") + ".podcastAds"
  }

  /// Registers the task while the app launches, as iOS requires.
  static func registerBackgroundTask() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      PodcastAdFinder.shared.runInBackground(task)
    }
  }

  /// Takes stock of the downloads and listens for the app coming to the front and leaving.
  /// Called while the app launches (also when iOS launches it in the background).
  func start() {
    let first = lock.withLock { () -> Bool in
      defer { started = true }
      return !started
    }
    guard first else { return }
    let center = NotificationCenter.default
    center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) {
      [weak self] _ in
      self?.lock.withLock { self?.appActive = true }
      self?.forgetFailures()
      self?.scan()
    }
    center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) {
      [weak self] _ in
      self?.lock.withLock { self?.appActive = false }
      if self?.hasWork == true { self?.askForBackgroundTime(force: true) }
    }
    DispatchQueue.main.async { [weak self] in
      let active = UIApplication.shared.applicationState == .active
      self?.lock.withLock { self?.appActive = active }
      self?.scan()
    }
  }

  /// Asks iOS for a turn on the charger. A new request replaces an earlier one; asking more
  /// than once a minute is skipped unless `force`.
  func askForBackgroundTime(force: Bool = false) {
    let skip = lock.withLock { () -> Bool in
      if !force, let last = lastAsked, Date().timeIntervalSince(last) < 60 { return true }
      lastAsked = Date()
      return false
    }
    guard !skip else { return }
    let request = BGProcessingTaskRequest(identifier: Self.identifier)
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = true
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("Podcasts: could not ask for background time to find ads: \(error)")
    }
  }

  /// iOS gave a turn. Finds ads until the work is done or iOS says the time is up.
  func runInBackground(_ task: BGTask) {
    lock.withLock { inBackgroundTask = true }
    task.expirationHandler = { [weak self] in
      self?.lock.withLock { self?.inBackgroundTask = false }
    }
    Task { [self] in
      scan()
      let running = lock.withLock { worker }
      await running?.value
      lock.withLock { inBackgroundTask = false }
      let left = hasWork
      if left { askForBackgroundTime(force: true) }
      task.setTaskCompleted(success: !left)
    }
  }
}
