// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The downloads' and transcripts' part of the app's launch. iOS may start the app in the background only to
// deliver downloads that finished while it was closed; there is no JavaScript then, so the
// download session is made here, while the app launches, and iOS's completion handler is kept
// until the session has handled its events.
import ExpoModulesCore
import UIKit

public final class PodcastsAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    PodcastDownloader.shared.start()
    // A background task has to be registered before the launch is over.
    PodcastTranscriber.registerBackgroundTask()
    PodcastTranscriber.shared.start()
    PodcastAdFinder.registerBackgroundTask()
    PodcastAdFinder.shared.start()
    return true
  }

  public func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    PodcastDownloader.shared.attach(identifier: identifier, completionHandler: completionHandler)
  }
}
