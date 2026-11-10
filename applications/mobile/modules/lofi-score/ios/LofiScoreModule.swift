// LOFI-FORK: the Storyteller Lofi fork's native module (see FORK.md).
//
// One music host per app. It follows the audiobook player through the hooks in
// modules/readium/ios/LofiNarratorBridge.swift and plays inside the narrator's own audio
// session: it never changes the session, Now Playing or the remote commands. The one thing
// it asks of the narrator is a short hold where the atmosphere swells or hushes.

import ExpoModulesCore
import LofiScoreHost
import Readium
import UIKit
import UniformTypeIdentifiers

public final class LofiScoreModule: Module {
  public func definition() -> ModuleDefinition {
    Name("LofiScore")

    OnCreate {
      LofiScoreRuntime.shared.start()
    }

    AsyncFunction("getStatus") { () async -> [String: Any] in
      await LofiScoreRuntime.shared.host.status().jsonObject()
    }

    AsyncFunction("setEnabled") { (enabled: Bool) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setEnabled(enabled)
      return await host.status().jsonObject()
    }

    AsyncFunction("setMutedInCar") { (muted: Bool) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setMutedInCar(muted)
      return await host.status().jsonObject()
    }

    // The music's level under the voice, in dB. null goes back to the default.
    AsyncFunction("setMusicLevel") { (level: Double?) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setMusicLevel(dB: level)
      return await host.status().jsonObject()
    }

    // Shows the Files folder picker, copies the music into the app and keeps a link to the
    // folder, so whatever is added to it later (scores from the Mac, new sounds or tracks)
    // is copied without importing again. Resolves to null when the listener cancels.
    AsyncFunction("importMusicFolder") { () async throws -> [String: Any]? in
      guard let folder = await LofiFolderPicker.pick() else { return nil }
      let summary = try await LofiScoreRuntime.shared.host.linkMusicFolder(folder)
      return [
        "folderName": summary.folderName,
        "tracks": summary.tracks,
        "moodTracks": summary.moodTracks,
        "hasClassifier": summary.hasClassifier,
        "notDownloaded": summary.notDownloaded,
        "atmosphereRecordings": summary.atmosphereRecordings,
        "atmosphereTracks": summary.atmosphereTracks,
      ]
    }

    // Looks at the linked music folder now and copies what is new. Resolves to null when
    // no folder is linked; rejects when the folder cannot be read.
    AsyncFunction("syncMusicFolder") { () async throws -> [String: Any]? in
      guard let summary = try await LofiScoreRuntime.shared.host.syncMusicFolder(reason: .manual) else { return nil }
      return [
        "folderName": summary.folderName,
        "added": summary.added,
        "updated": summary.updated,
        "notDownloaded": summary.notDownloaded,
        "music": summary.music,
        "models": summary.models,
        "moodTracks": summary.moodTracks,
        "atmosphereTracks": summary.atmosphereTracks,
        "atmosphereRecordings": summary.atmosphereRecordings,
        "fresh": summary.fresh,
        "description": summary.description,
      ]
    }

    // Forgets the linked folder; the music already copied stays.
    AsyncFunction("unlinkMusicFolder") { () async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.unlinkMusicFolder()
      return await host.status().jsonObject()
    }

    // Keeps a score fetched from the server (GET /api/v2/books/<id>/lofi-score) with the
    // book, and reads the book again with it when it is the one open. Rejects when the
    // text is not a score or the book is not on the device.
    AsyncFunction("installBookScore") { (bookUuid: String, score: String) async throws -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      try await host.installScore(Data(score.utf8), forBook: bookUuid)
      return await host.status().jsonObject()
    }

    // Back from the background: anything new in the linked folder (a score the Mac
    // finished) is copied, at most once a minute.
    OnAppEntersForeground {
      LofiScoreRuntime.shared.host.syncMusicFolderIfDue(reason: .foreground)
    }

    // The imported music's CREDITS.md, or null.
    AsyncFunction("getMusicCredits") { () async -> String? in
      await LofiScoreRuntime.shared.host.musicCredits()
    }

    AsyncFunction("setAtmosphereEnabled") { (enabled: Bool) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setAtmosphereEnabled(enabled)
      return await host.status().jsonObject()
    }

    // The atmosphere's level under the voice, in dB. null goes back to the default.
    AsyncFunction("setAtmosphereLevel") { (level: Double?) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setAtmosphereLevel(dB: level)
      return await host.status().jsonObject()
    }

    // Short narration pauses where the atmosphere swells or hushes.
    AsyncFunction("setAtmospherePauses") { (enabled: Bool) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setAtmospherePausesEnabled(enabled)
      return await host.status().jsonObject()
    }

    // One-off sounds (a knock, a clap of thunder) on their sentences. Off by default.
    AsyncFunction("setAtmosphereOneShots") { (enabled: Bool) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setAtmosphereOneShotsEnabled(enabled)
      return await host.status().jsonObject()
    }

    // The imported sounds' Atmosphere/CREDITS.md, or null.
    AsyncFunction("getAtmosphereCredits") { () async -> String? in
      await LofiScoreRuntime.shared.host.atmosphereCredits()
    }

    AsyncFunction("removeImportedMusic") { () async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.removeImportedMusic()
      return await host.status().jsonObject()
    }

    // The music panel's "Wrong mood" button: the music moves to the named mood, or to the
    // engine's next guess with null, and the tap is logged. Resolves to null when nothing
    // was playing or nothing changed.
    AsyncFunction("markWrongMood") { (mood: String?) async -> [String: Any]? in
      await LofiScoreRuntime.shared.host.markWrongMood(named: mood)?.jsonObject()
    }

    // The wrong-mood log as text to share, or null when nothing was marked yet.
    AsyncFunction("getMoodFeedback") { () async -> String? in
      await LofiScoreRuntime.shared.host.moodFeedbackText()
    }

    // Music while reading on screen with the narration stopped.
    AsyncFunction("setFollowsReading") { (enabled: Bool) async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.setFollowsReading(enabled)
      return await host.status().jsonObject()
    }

    // The page now starts at the clip at `start` seconds into `relativeUrl` (the audio file),
    // as the app found it to keep the audio in step with the page.
    AsyncFunction("readerReached") { (bookUuid: String, relativeUrl: String, start: Double) async in
      guard let clip = await AudiobookPlayerActor.shared.lofiClip(audioResource: relativeUrl, at: start) else { return }
      LofiScoreRuntime.shared.host.readerReached(bookID: bookUuid, clip: NarratorClip(clip))
    }

    // The reader left the book or the app: the music that follows the pages stops.
    AsyncFunction("readerStopped") {
      LofiScoreRuntime.shared.host.readerStopped()
    }
  }
}

/// The app's one music host, wired to the audiobook player once.
final class LofiScoreRuntime: @unchecked Sendable {
  static let shared = LofiScoreRuntime()

  let host: LofiMusicHost
  private let holds: LofiNarrationHoldRelay
  private let lock = NSLock()
  private var started = false

  private init() {
    let holds = LofiNarrationHoldRelay()
    let host = LofiMusicHost.forApp(holdNarration: { holds.request(seconds: $0) })
    holds.attach(host)
    self.host = host
    self.holds = holds
  }

  func start() {
    let first: Bool = lock.withLock {
      defer { started = true }
      return !started
    }
    guard first else { return }
    host.start()
    let host = self.host
    let holds = self.holds
    Task {
      let player = AudiobookPlayerActor.shared
      await player.lofiObserve(
        track: { track in
          host.narratorLoadedBook(id: track.bookUuid, trackFile: track.fileURL)
        },
        playing: { isPlaying, clip in
          holds.narratorPlayingChanged(isPlaying)
          host.narratorPlayingChanged(isPlaying)
          if let clip {
            host.narratorClipStarted(NarratorClip(clip), audioTime: clip.playbackPosition)
          }
        },
        clip: { clip in
          host.narratorClipStarted(NarratorClip(clip))
        }
      )
      // In case a book was already loaded before the observers were in place.
      if let state = await player.lofiState() {
        host.narratorLoadedBook(id: state.track.bookUuid, trackFile: state.track.fileURL)
        if state.isPlaying {
          holds.narratorPlayingChanged(true)
          host.narratorPlayingChanged(true)
        }
        if let clip = state.clip {
          host.narratorClipStarted(NarratorClip(clip), audioTime: clip.playbackPosition)
        }
      }
    }
  }
}

/// Passes the atmosphere's requests for a short narration hold to the audiobook player, and
/// the player's answers back. The host wants an answer at once, so the relay answers from
/// what the narrator last reported, and the player has the final say: a hold it refuses
/// comes back as `narrationHold(began: false)` with no `true` before it.
final class LofiNarrationHoldRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var narratorPlaying = false
  private var pending = false
  private var host: LofiMusicHost?

  func attach(_ host: LofiMusicHost) {
    lock.withLock { self.host = host }
  }

  func narratorPlayingChanged(_ isPlaying: Bool) {
    lock.withLock { narratorPlaying = isPlaying }
  }

  func request(seconds: Double) -> Bool {
    let accepted: Bool = lock.withLock {
      guard narratorPlaying, !pending else { return false }
      pending = true
      return true
    }
    guard accepted else { return false }
    Task {
      let armed = await AudiobookPlayerActor.shared.lofiHoldAfterCurrentClip(seconds: seconds) { [self] event in
        switch event {
        case .began: report(began: true, over: false)
        case .ended, .dropped: report(began: false, over: true)
        }
      }
      if !armed { report(began: false, over: true) }
    }
    return true
  }

  private func report(began: Bool, over: Bool) {
    let host: LofiMusicHost? = lock.withLock {
      if over { pending = false }
      return self.host
    }
    host?.narrationHold(began: began)
  }
}

extension NarratorClip {
  init(_ clip: LofiNarratorClip) {
    self.init(
      textResource: clip.textResource,
      fragmentId: clip.fragmentId,
      audioResource: clip.audioResource,
      start: clip.start,
      end: clip.end
    )
  }
}

/// The Files app's folder picker, for importing a music folder (from iCloud Drive, say).
@MainActor
final class LofiFolderPicker: NSObject, UIDocumentPickerDelegate {
  private static var current: LofiFolderPicker?
  private var continuation: CheckedContinuation<URL?, Never>?

  static func pick() async -> URL? {
    await withCheckedContinuation { continuation in
      let picker = LofiFolderPicker()
      picker.continuation = continuation
      current = picker
      let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      controller.delegate = picker
      controller.allowsMultipleSelection = false
      guard let presenter = topViewController() else {
        picker.finish(nil)
        return
      }
      presenter.present(controller, animated: true)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(urls.first)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  private func finish(_ url: URL?) {
    continuation?.resume(returning: url)
    continuation = nil
    Self.current = nil
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    var controller = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
      controller = presented
    }
    return controller
  }
}
