#if canImport(AVFoundation)
import AVFoundation
import Foundation
import LofiAtmosphere

extension LofiAtmosphereHost {
    /// The host for the iPhone app:
    ///
    /// - the imported sounds in `Application Support/LofiScore/Music` (left out of backups;
    ///   the folder keeps the name it had when it also held the music, so an update keeps
    ///   what was imported and the linked folder),
    /// - stand-in sounds synthesised into `Caches/LofiScore/Atmosphere` for the sounds not
    ///   imported,
    /// - book scores also read from `Application Support/LofiScore/Scores`, and atmosphere
    ///   tracks from `Application Support/LofiScore/AtmosphereTracks`,
    /// - books where Storyteller unzips them, `Documents/books/extracted/<uuid>/readaloud`,
    /// - AVAudioEngine for the sound, inside the narrator's own audio session; which
    ///   recordings it may play comes from the Info.plist (`soundEditionInfoKey`),
    /// - `holdNarration`, from the app's narrator, for the atmosphere's short pauses,
    /// - the shelved music's stand-in tracks (`Caches/LofiScore/Placeholders`) removed at launch.
    public static func forApp(
        settings: AtmosphereSettings = AtmosphereSettings(),
        holdNarration: (@Sendable (_ seconds: Double) -> Bool)? = nil
    ) -> LofiAtmosphereHost {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LofiScore", isDirectory: true)
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LofiScore", isDirectory: true)
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return LofiAtmosphereHost(environment: Environment(
            settings: settings,
            soundsFolder: support.appendingPathComponent("Music", isDirectory: true),
            scoreFolders: [support.appendingPathComponent("Scores", isDirectory: true)],
            atmosphereTrackFolders: [support.appendingPathComponent("AtmosphereTracks", isDirectory: true)],
            booksFolder: documents.appendingPathComponent("books/extracted", isDirectory: true),
            makeBackend: { AVAmbienceBackend() },
            placeholderFolder: caches.appendingPathComponent("Atmosphere", isDirectory: true),
            soundEdition: soundEdition(Bundle.main.object(forInfoDictionaryKey: soundEditionInfoKey)),
            holdNarration: holdNarration,
            staleFolders: [caches.appendingPathComponent("Placeholders", isDirectory: true)]
        ))
    }
}
#endif
