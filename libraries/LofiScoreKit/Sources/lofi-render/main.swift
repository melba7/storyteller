// Renders the demo story to an audio file: the Mac's voice reads "The Green Lantern" while
// the real player, on an offline AVAudioEngine, follows its mood with the music underneath.
// Nothing is played out loud. Next to the audio it writes a .txt timeline to read along.
//
//   swift run -c release lofi-render [--music FOLDER] [--out FILE.m4a] [--voice NAME]
//                                    [--rate WPM] [--real-timings] [--noise X] [--seed N]
//
// Without --music it uses the synthesised placeholder tracks.

#if os(macOS)
import AVFoundation
import Foundation
import LofiAudio
import LofiDemoKit
import LofiDirector
import LofiPlaceholders
import LofiScoreCore

func usage() -> Never {
    print("""
    usage: lofi-render [--music FOLDER] [--out FILE.m4a] [--voice NAME] [--rate WPM]
                       [--real-timings] [--noise X] [--seed N]

      --music FOLDER   music library: one folder per mood, or a library.json (default: placeholders)
      --out FILE       where to write the AAC file (default: green-lantern-demo.m4a)
      --voice NAME     a macOS voice, as `say -v '?'` lists them (default: the system voice)
      --rate WPM       speaking rate in words per minute (default 165)
      --real-timings   the app's director settings (90 s dwell, 60 s smoothing) instead of the
                       demo's faster ones; few changes happen in a five-minute story
      --noise X        chance that a reading picks a neighbouring mood (default 0.15)
      --seed N         seed for readings and track choice (default 1)
    """)
    exit(2)
}

var musicPath: String?
var outPath = "green-lantern-demo.m4a"
var voiceName: String?
var wordsPerMinute = 165
var realTimings = false
var noise = 0.15
var seed: UInt64 = 1
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--music":
        guard let value = arguments.popFirst() else { usage() }
        musicPath = value
    case "--out":
        guard let value = arguments.popFirst() else { usage() }
        outPath = value
    case "--voice":
        guard let value = arguments.popFirst() else { usage() }
        voiceName = value
    case "--rate":
        guard let value = arguments.popFirst().flatMap(Int.init), value >= 80, value <= 400 else { usage() }
        wordsPerMinute = value
    case "--real-timings":
        realTimings = true
    case "--noise":
        guard let value = arguments.popFirst().flatMap(Double.init), value >= 0, value <= 1 else { usage() }
        noise = value
    case "--seed":
        guard let value = arguments.popFirst().flatMap(UInt64.init) else { usage() }
        seed = value
    case "-h", "--help":
        usage()
    default:
        usage()
    }
}

func expand(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

let sampleRate = 44_100.0
let story = DemoStory.greenLantern
let started = Date()

func elapsed() -> String {
    String(format: "%5.1fs", Date().timeIntervalSince(started))
}

do {
    // 1. Music.
    let library: MusicLibrary
    if let musicPath {
        library = try MusicLibrary.load(from: expand(musicPath))
        let measured = library.tracks.filter { $0.loudness != nil }.count
        print("\(elapsed())  music: \(library.tracks.count) tracks from \(library.root.path) (\(measured) with measured loudness)")
    } else {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        library = try PlaceholderLibrary.prepare(at: caches.appendingPathComponent("LofiScoreKit/Placeholders", isDirectory: true))
        print("\(elapsed())  music: \(library.tracks.count) placeholder tracks")
    }
    if !library.emptyBuckets.isEmpty {
        print("         no tracks for \(library.emptyBuckets.map(\.rawValue).joined(separator: ", ")); the nearest mood stands in")
    }

    // 2. The voice, one file per sentence (cached between runs).
    let voiceTag = (voiceName ?? "system").replacingOccurrences(of: "/", with: "-") + "-\(wordsPerMinute)"
    let voiceCache = FileManager.default.temporaryDirectory.appendingPathComponent("lofi-render-voice/\(voiceTag)", isDirectory: true)
    try FileManager.default.createDirectory(at: voiceCache, withIntermediateDirectories: true)
    var voices: [String: [Float]] = [:]
    for sentence in story.sentences where voices[sentence.text] == nil {
        let file = voiceCache.appendingPathComponent(String(format: "%03d.aiff", sentence.globalIndex))
        if !FileManager.default.fileExists(atPath: file.path) {
            try SystemVoice.render(sentence.text, to: file, voice: voiceName, wordsPerMinute: wordsPerMinute)
        }
        let samples = try AudioFileIO.readMono(file, sampleRate: sampleRate)
        voices[sentence.text] = AudioFileIO.trimSilence(samples, sampleRate: sampleRate)
        if (sentence.globalIndex + 1) % 15 == 0 {
            print("\(elapsed())  voice: \(sentence.globalIndex + 1)/\(story.sentences.count) sentences")
        }
    }
    let spoken = voices.values.reduce(0) { $0 + Double($1.count) } / sampleRate
    print("\(elapsed())  voice: \(story.sentences.count) sentences, \(Int(spoken)) s of speech")

    // 3. The story through the real player, on an offline engine.
    let recorder = try OfflineMusicRecorder(sampleRate: sampleRate)
    var config = ScoreConfig()
    config.director = realTimings ? DirectorConfig() : .demo
    let run = OfflineStoryRun(
        story: story,
        library: library,
        backend: recorder.backend,
        config: config,
        moodSource: ScriptedMoodSource(noise: noise, seed: seed),
        rotationSeed: seed,
        voiceDuration: { text in Double(voices[text]?.count ?? 0) / sampleRate }
    )
    let report = try run.run { start, duration in
        try recorder.render(until: start + duration)
    }
    let errors = report.events.compactMap { timed -> String? in
        if case let .error(message) = timed.event { return message }
        return nil
    }
    print("\(elapsed())  music: \(Int(report.duration)) s rendered, \(report.decisions.count) mood changes"
        + (errors.isEmpty ? "" : ", \(errors.count) player errors"))
    for message in Set(errors) {
        print("         \(message)")
    }
    guard report.finished else {
        print("lofi-render: the story did not finish")
        exit(1)
    }

    // 4. Mix and write.
    let voiceTrack = OfflineMix.voiceTrack(clips: report.clips, sampleRate: sampleRate, frames: recorder.audio.frames) { clip in
        voices[clip.text]
    }
    let mix = OfflineMix.mix(voice: voiceTrack, music: recorder.audio)
    let out = expand(outPath)
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try AudioFileIO.writeAAC(mix.audio, to: out)
    let timelineURL = out.deletingPathExtension().appendingPathExtension("txt")
    var timeline = OfflineMix.timeline(report, story: story, library: library)
    timeline += String(
        format: "Voice %.1f LUFS before levelling; music bed %.1f LUFS; whole file %.1f LUFS, peak %.1f dBTP.\n",
        -18 - mix.voiceGainDB, mix.musicLoudness, mix.outputLoudness, mix.outputPeak
    )
    timeline += realTimings ? "Director: the app's settings.\n" : "Director: demo timings (12 s smoothing, 20 s dwell), so changes come faster than in the app.\n"
    try timeline.write(to: timelineURL, atomically: true, encoding: .utf8)
    print(String(
        format: "%@  wrote %@ (%d:%02d, %.1f LUFS, peak %.1f dBTP) and %@",
        elapsed(), out.path, Int(mix.audio.duration) / 60, Int(mix.audio.duration) % 60,
        mix.outputLoudness, mix.outputPeak, timelineURL.lastPathComponent
    ))
} catch {
    print("lofi-render: \(error)")
    exit(1)
}
#else
print("lofi-render needs macOS: it uses AVAudioEngine and the system voice.")
#endif
