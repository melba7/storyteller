#if canImport(AVFoundation)
import AVFoundation
import Foundation
import LofiAudio

extension LofiMusicHost {
    /// The host for the iPhone app:
    ///
    /// - imported music in `Application Support/LofiScore/Music` (left out of backups),
    /// - stand-in tracks synthesised into `Caches/LofiScore/Placeholders` until then,
    /// - mood tracks also read from `Application Support/LofiScore/MoodTracks`,
    /// - books where Storyteller unzips them, `Documents/books/extracted/<uuid>/readaloud`,
    /// - AVAudioEngine for the sound, inside the narrator's own audio session.
    public static func forApp(settings: MusicSettings = MusicSettings()) -> LofiMusicHost {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LofiScore", isDirectory: true)
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LofiScore", isDirectory: true)
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return LofiMusicHost(environment: Environment(
            settings: settings,
            musicFolder: support.appendingPathComponent("Music", isDirectory: true),
            placeholderFolder: caches.appendingPathComponent("Placeholders", isDirectory: true),
            moodTrackFolders: [support.appendingPathComponent("MoodTracks", isDirectory: true)],
            booksFolder: documents.appendingPathComponent("books/extracted", isDirectory: true),
            makeBackend: { AVAudioEngineBackend() }
        ))
    }
}
#endif
