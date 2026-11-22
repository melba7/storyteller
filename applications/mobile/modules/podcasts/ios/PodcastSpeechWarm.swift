// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Loads the speech model when the app comes to the front with Skip ads on, so the first look at
// a stream's head does not wait for it. The system keeps the model in memory for the life of the
// app once it has been loaded (`AppleSpeech.warm`), about 100 MB. Nothing is loaded when Skip
// ads is off, when the speech model is not on the phone yet (it is never downloaded here), or
// after it has been loaded once.

import Foundation
import PodcastSpeech
import PodcastTranscripts
import UIKit

final class PodcastSpeechWarm: @unchecked Sendable {
  static let shared = PodcastSpeechWarm()

  private let lock = NSLock()
  private var started = false
  private var working = false
  private var loaded = false

  /// Listens for the app coming to the front. Called while the app launches, before it is
  /// active; an app that iOS starts in the background never comes to the front, so it loads
  /// nothing.
  func start() {
    let first = lock.withLock { () -> Bool in
      defer { started = true }
      return !started
    }
    guard first else { return }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
    ) { [weak self] _ in
      self?.warmIfWanted()
    }
  }

  private func warmIfWanted() {
    guard AdSkipDefaults.settings.skipsAnySort else { return }
    let go = lock.withLock { () -> Bool in
      guard !loaded, !working else { return false }
      working = true
      return true
    }
    guard go else { return }
    let locale = LocalePick.identifier(
      feedLanguage: nil, phone: Locale.preferredLanguages.first ?? "en-US")
    Task.detached(priority: .utility) { [self] in
      let ready = await AppleSpeech.warm(locale: locale)
      lock.withLock {
        working = false
        loaded = ready
      }
    }
  }
}
