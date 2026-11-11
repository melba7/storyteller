#if canImport(AVFoundation)
import AVFoundation
import Foundation
import LofiAtmosphere
import LofiAudio

extension LofiMusicHost {
    /// The host for the iPhone app:
    ///
    /// - imported music in `Application Support/LofiScore/Music` (left out of backups),
    /// - stand-in tracks synthesised into `Caches/LofiScore/Placeholders` until then,
    /// - mood tracks also read from `Application Support/LofiScore/MoodTracks`,
    /// - books where Storyteller unzips them, `Documents/books/extracted/<uuid>/readaloud`,
    /// - AVAudioEngine for the sound, inside the narrator's own audio session,
    /// - the atmosphere: imported sounds in `Music/Atmosphere`, stand-ins synthesised into
    ///   `Caches/LofiScore/Atmosphere`, atmosphere tracks also read from
    ///   `Application Support/LofiScore/AtmosphereTracks`, and a second AVAudioEngine of its own;
    ///   which recordings it may play comes from the Info.plist (`soundEditionInfoKey`),
    /// - `holdNarration`, from the app's narrator, for the atmosphere's short pauses,
    /// - the "Wrong mood" log in `Application Support/LofiScore/Feedback`.
    public static func forApp(
        settings: MusicSettings = MusicSettings(),
        holdNarration: (@Sendable (_ seconds: Double) -> Bool)? = nil
    ) -> LofiMusicHost {
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
            makeBackend: { AVAudioEngineBackend() },
            makeAmbienceBackend: { AVAmbienceBackend() },
            atmospherePlaceholderFolder: caches.appendingPathComponent("Atmosphere", isDirectory: true),
            atmosphereTrackFolders: [support.appendingPathComponent("AtmosphereTracks", isDirectory: true)],
            soundEdition: soundEdition(Bundle.main.object(forInfoDictionaryKey: soundEditionInfoKey)),
            holdNarration: holdNarration,
            feedbackFolder: support.appendingPathComponent("Feedback", isDirectory: true)
        ))
    }
}
#endif
