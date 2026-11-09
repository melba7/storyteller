// LOFI-FORK: the Storyteller Lofi fork's native module (see FORK.md).
//
// One music host per app. It follows the audiobook player through the read-only hooks in
// modules/readium/ios/LofiNarratorBridge.swift and plays inside the narrator's own audio
// session: it never changes the session, Now Playing or the remote commands.

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

    // Shows the Files folder picker and copies the music into the app. Resolves to null
    // when the listener cancels.
    AsyncFunction("importMusicFolder") { () async throws -> [String: Any]? in
      guard let folder = await LofiFolderPicker.pick() else { return nil }
      let summary = try await LofiScoreRuntime.shared.host.importMusic(from: folder)
      return [
        "folderName": summary.folderName,
        "tracks": summary.tracks,
        "moodTracks": summary.moodTracks,
        "hasClassifier": summary.hasClassifier,
        "notDownloaded": summary.notDownloaded,
      ]
    }

    // The imported music's CREDITS.md, or null.
    AsyncFunction("getMusicCredits") { () async -> String? in
      await LofiScoreRuntime.shared.host.musicCredits()
    }

    AsyncFunction("removeImportedMusic") { () async -> [String: Any] in
      let host = LofiScoreRuntime.shared.host
      await host.removeImportedMusic()
      return await host.status().jsonObject()
    }
  }
}

/// The app's one music host, wired to the audiobook player once.
final class LofiScoreRuntime: @unchecked Sendable {
  static let shared = LofiScoreRuntime()

  let host = LofiMusicHost.forApp()
  private let lock = NSLock()
  private var started = false

  func start() {
    let first: Bool = lock.withLock {
      defer { started = true }
      return !started
    }
    guard first else { return }
    host.start()
    let host = self.host
    Task {
      let player = AudiobookPlayerActor.shared
      await player.lofiObserve(
        track: { track in
          host.narratorLoadedBook(id: track.bookUuid, trackFile: track.fileURL)
        },
        playing: { isPlaying, clip in
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
          host.narratorPlayingChanged(true)
        }
        if let clip = state.clip {
          host.narratorClipStarted(NarratorClip(clip), audioTime: clip.playbackPosition)
        }
      }
    }
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
