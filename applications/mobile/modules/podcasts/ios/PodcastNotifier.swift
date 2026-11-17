// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Local notifications for new episodes, through UNUserNotificationCenter. JavaScript decides
// what to say (newEpisodeNotice.ts); this only asks for permission and posts. expo-notifications
// is not part of the app, and a local notification needs no push entitlement.

import Foundation
import UserNotifications

final class PodcastNotifier: NSObject, UNUserNotificationCenterDelegate {
  static let shared = PodcastNotifier()

  /// Every notification of ours has an id that starts with this.
  static let idPrefix = "podcasts.new-episodes."

  private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

  /// Lets our notifications show as a banner also while the app is open. Called while the app
  /// launches, also when iOS starts it in the background. Another delegate is left alone.
  func install() {
    if center.delegate == nil { center.delegate = self }
  }

  /// "granted", "denied" or "undetermined" (not asked yet).
  func permission() async -> String {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral: return "granted"
    case .denied: return "denied"
    default: return "undetermined"
    }
  }

  /// Asks the listener once (iOS shows its own question) and returns whether it is allowed.
  func requestPermission() async -> Bool {
    do {
      return try await center.requestAuthorization(options: [.alert, .sound])
    } catch {
      NSLog("Podcasts: notification permission failed: \(error)")
      return false
    }
  }

  /// Shows a notification now. A later one with the same id replaces it. Nothing happens when
  /// the listener has not allowed notifications.
  func post(id: String, title: String, body: String) async throws {
    guard await permission() == "granted" else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    try await center.add(
      UNNotificationRequest(identifier: Self.idPrefix + id, content: content, trigger: nil))
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    notification.request.identifier.hasPrefix(Self.idPrefix) ? [.banner, .list, .sound] : []
  }
}
