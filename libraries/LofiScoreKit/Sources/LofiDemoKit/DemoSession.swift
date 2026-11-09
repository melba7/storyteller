#if canImport(SwiftUI) && canImport(AVFoundation)
import AVFoundation
import Combine
import Foundation
import LofiAudio
import LofiDirector
import LofiPlaceholders
import LofiScoreCore

/// The demo app's model: a music library, the real AVAudioEngine player, and a pretend
/// narrator reading the demo story (optionally out loud).
///
/// Use it from the main thread only. The player runs on its own queue and reports back
/// through snapshots polled ten times a second.
public final class DemoSession: ObservableObject {
    public enum LibraryState: Equatable {
        case preparing(done: Int, total: Int)
        case ready(source: String, trackCount: Int, emptyMoods: [MoodBucket])
        case failed(String)
    }

    public struct LogLine: Identifiable, Hashable {
        public let id: Int
        public let time: String
        public let text: String
    }

    @Published public private(set) var libraryState: LibraryState = .preparing(done: 0, total: 0)
    @Published public private(set) var snapshot: PlayerSnapshot?
    @Published public private(set) var log: [LogLine] = []
    @Published public private(set) var sentenceIndex = 0
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isBookOpen = false
    @Published public private(set) var lastReading: MoodObservation?

    @Published public var speakAloud = false { didSet { narrator?.speaker = speakAloud ? speaker : nil } }
    @Published public var fastTimings = true { didSet { if oldValue != fastTimings { rebuild() } } }
    @Published public var narratorRate = 1.0 { didSet { narrator?.settings.rate = narratorRate } }
    @Published public var readingNoise = 0.15 { didSet { narrator?.moodSource.noise = readingNoise } }
    @Published public var musicEnabled = true { didSet { player?.setEnabled(musicEnabled) } }
    @Published public var muteInCar = false { didSet { player?.setMutedRoutes(muteInCar ? [.carPlay] : []) } }
    @Published public var bedLevelDB = -12.0 { didSet { pushDucking() } }
    @Published public var gapLiftDB = 4.0 { didSet { pushDucking() } }
    @Published public var musicVolume = 1.0 { didSet { player?.setMusicVolume(musicVolume) } }

    public let story = DemoStory.greenLantern

    private var library: MusicLibrary?
    private var librarySource = ""
    private var player: LofiScorePlayer?
    private var narrator: StoryNarrator?
    private let speaker = SpeechSpeaker()
    private var pollTimer: Timer?
    private var logCount = 0
    private var scopedFolder: URL?
    private let started = Date()
    private var autoplayPending: Bool

    /// Launch arguments for unattended runs (the Simulator, screenshots):
    /// `-LofiDemoAutoplay YES` starts reading as soon as the music is ready,
    /// `-LofiDemoSilent YES` sets the music volume to zero and keeps the voice off,
    /// `-LofiDemoMusicFolder /path` uses that folder instead of the placeholders.
    public init() {
        let defaults = UserDefaults.standard
        autoplayPending = defaults.bool(forKey: "LofiDemoAutoplay")
        if defaults.bool(forKey: "LofiDemoSilent") {
            musicVolume = 0
            speakAloud = false
        }
        if let path = defaults.string(forKey: "LofiDemoMusicFolder"),
           let library = try? MusicLibrary.load(from: URL(fileURLWithPath: path, isDirectory: true)) {
            use(library, source: URL(fileURLWithPath: path).lastPathComponent)
        } else {
            preparePlaceholders()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    deinit {
        pollTimer?.invalidate()
        scopedFolder?.stopAccessingSecurityScopedResource()
    }

    public var currentSentence: DemoSentence { story.sentences[sentenceIndex] }

    // MARK: - Library

    /// Where the generated placeholder tracks live (a cache: safe to delete).
    public static var placeholderFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("LofiScoreKit/Placeholders", isDirectory: true)
    }

    public func preparePlaceholders() {
        libraryState = .preparing(done: 0, total: PlaceholderRecipe.defaults().count)
        let folder = Self.placeholderFolder
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let library = try PlaceholderLibrary.prepare(at: folder) { done, total, _ in
                    DispatchQueue.main.async { self?.libraryState = .preparing(done: done, total: total) }
                }
                DispatchQueue.main.async { self?.use(library, source: "Synthesised placeholders") }
            } catch {
                DispatchQueue.main.async { self?.libraryState = .failed("Could not make placeholders: \(error)") }
            }
        }
    }

    /// Uses a folder of real tracks: one subfolder per mood, or a library.json.
    public func useFolder(_ result: Result<URL, Error>) {
        switch result {
        case let .failure(error):
            addLog("Folder not opened: \(error.localizedDescription)")
        case let .success(url):
            let accessing = url.startAccessingSecurityScopedResource()
            do {
                let library = try MusicLibrary.load(from: url)
                scopedFolder?.stopAccessingSecurityScopedResource()
                scopedFolder = accessing ? url : nil
                use(library, source: url.lastPathComponent)
            } catch {
                if accessing { url.stopAccessingSecurityScopedResource() }
                addLog("\(url.lastPathComponent): \(error)")
            }
        }
    }

    private func use(_ library: MusicLibrary, source: String) {
        self.library = library
        librarySource = source
        libraryState = .ready(source: source, trackCount: library.tracks.count, emptyMoods: library.emptyBuckets)
        addLog("Library: \(source), \(library.tracks.count) tracks")
        rebuild()
        if autoplayPending {
            autoplayPending = false
            narrator?.play()
        }
    }

    // MARK: - Player

    private func rebuild() {
        guard let library else { return }
        let wasPlaying = narrator?.isPlaying ?? false
        let position = narrator?.index ?? 0
        narrator?.closeBook()
        narrator = nil
        player = nil

        var config = ScoreConfig()
        config.director = fastTimings ? .demo : DirectorConfig()
        config.ducking = ducking
        config.musicVolume = musicVolume
        config.mutedRoutes = muteInCar ? [.carPlay] : []
        let player = LofiScorePlayer(library: library, backend: AVAudioEngineBackend(), config: config)
        player.setEnabled(musicEnabled)
        player.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.record(event) }
        }

        let narrator = StoryNarrator(
            story: story,
            player: player,
            scheduler: DispatchScheduler(queue: .main),
            moodSource: ScriptedMoodSource(noise: readingNoise, seed: UInt64(Date().timeIntervalSince1970))
        )
        narrator.settings.rate = narratorRate
        narrator.speaker = speakAloud ? speaker : nil
        narrator.willStartPlaying = { DemoSession.activateAudioSession() }
        narrator.onChange = { [weak self] in self?.syncNarrator() }
        narrator.onReading = { [weak self] observation in
            self?.lastReading = observation
            self?.addLog("Reading @\(observation.globalSentenceIndex) \(observation.trigger.rawValue): "
                + "\(observation.reading.bucket.rawValue) \(Int(observation.reading.confidence * 100))%")
        }
        self.player = player
        self.narrator = narrator
        if position > 0 {
            narrator.seek(to: position)
        }
        if wasPlaying {
            narrator.play()
        }
        syncNarrator()
    }

    private var ducking: DuckingSettings {
        var settings = DuckingSettings()
        settings.bedLevelDB = bedLevelDB
        settings.gapLiftDB = gapLiftDB
        return settings
    }

    private func pushDucking() {
        player?.setDucking(ducking)
    }

    /// The demo is the host app here, so it owns the audio session, exactly as Storyteller's
    /// narrator does. LofiScoreKit itself never touches the session.
    static func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        #endif
    }

    // MARK: - Controls

    public func togglePlay() { narrator?.togglePlay() }
    public func skip(seconds: Double) { narrator?.skip(seconds: seconds) }
    public func nextChapter() { narrator?.nextChapter() }
    public func previousChapter() { narrator?.previousChapter() }
    public func sleep(after seconds: TimeInterval) {
        narrator?.sleep(after: seconds)
        addLog("Sleep timer: \(Int(seconds)) s")
    }

    public func toggleBook() {
        guard let narrator else { return }
        narrator.isBookOpen ? narrator.closeBook() : narrator.openBook()
    }

    public func jump(toChapter chapter: Int) {
        guard story.chapters.indices.contains(chapter) else { return }
        narrator?.seek(to: story.chapters[chapter].firstIndex)
    }

    // MARK: - State

    private func syncNarrator() {
        guard let narrator else { return }
        if sentenceIndex != narrator.index { sentenceIndex = narrator.index }
        if isPlaying != narrator.isPlaying { isPlaying = narrator.isPlaying }
        if isBookOpen != narrator.isBookOpen { isBookOpen = narrator.isBookOpen }
    }

    private func poll() {
        player?.snapshot { [weak self] snapshot in
            DispatchQueue.main.async { self?.snapshot = snapshot }
        }
    }

    private func record(_ event: PlayerEvent) {
        switch event {
        case let .moodChanged(decision):
            addLog("Mood → \(decision.bucket.rawValue) (\(decision.reason.rawValue), \(decision.transition.rawValue))")
        case let .trackStarted(id, mood, deck, offset):
            addLog("Deck \(deck): \(id) for \(mood.rawValue)" + (offset > 0.5 ? String(format: " from %.0f s", offset) : ""))
        case let .crossfadeStarted(_, to, transition, duration):
            addLog(String(format: "Crossfade to %@ (%@, %.1f s)", to, transition.rawValue, duration))
        case let .crossfadeReversed(deck):
            addLog("Crossfade reversed toward deck \(deck)")
        case .crossfadeFinished:
            break
        case let .fallback(requested, used):
            addLog("No \(requested.rawValue) tracks: using \(used.rawValue)")
        case .engineStarted:
            addLog("Audio engine started")
        case .engineStopped:
            addLog("Audio engine stopped (paused 2 min)")
        case let .engineRestarting(reason):
            addLog("Audio engine restarting: \(reason.rawValue)")
        case let .routeChanged(route):
            addLog("Output: \(route.rawValue)")
        case let .bookOpened(id):
            addLog("Book opened: \(id)")
        case .bookClosed:
            addLog("Book closed")
        case let .error(message):
            addLog("⚠️ \(message)")
        }
    }

    private func addLog(_ text: String) {
        logCount += 1
        let time = String(format: "%5.1f", Date().timeIntervalSince(started))
        log.insert(LogLine(id: logCount, time: time, text: text), at: 0)
        if log.count > 80 {
            log.removeLast(log.count - 80)
        }
    }
}

/// Reads sentences aloud with the system voice.
///
/// Used only from the main queue (the demo's narrator runs there), and the delegate
/// callback hops back to it, so the synthesizer is never shared across threads.
final class SpeechSpeaker: NSObject, SentenceSpeaker, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Double, completion: @escaping () -> Void) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, scaled))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        current = utterance
        self.completion = completion
        synthesizer.speak(utterance)
    }

    func stop() {
        current = nil
        completion = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, utterance === self.current else { return }
            let completion = self.completion
            self.current = nil
            self.completion = nil
            completion?()
        }
    }
}
#endif
