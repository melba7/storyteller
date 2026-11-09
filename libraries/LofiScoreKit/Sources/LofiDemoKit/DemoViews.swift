#if canImport(SwiftUI) && canImport(AVFoundation)
import LofiAudio
import LofiDirector
import LofiScoreCore
import SwiftUI
import UniformTypeIdentifiers

/// The whole demo: the story, the transport, what the music is doing and why.
public struct DemoRootView: View {
    @StateObject private var session = DemoSession()
    @State private var choosingFolder = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("LofiScore demo")
                    .font(.title2.bold())
                LibraryBanner(state: session.libraryState)
                StoryCard(session: session)
                TransportCard(session: session)
                MusicCard(snapshot: session.snapshot)
                DirectorCard(snapshot: session.snapshot, lastReading: session.lastReading)
                SettingsCard(session: session, choosingFolder: $choosingFolder)
                LogCard(lines: session.log)
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 380, minHeight: 560)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            session.useFolder(result)
        }
    }
}

// MARK: - Cards

struct LibraryBanner: View {
    let state: DemoSession.LibraryState

    var body: some View {
        switch state {
        case let .preparing(done, total):
            HStack(spacing: 10) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Making placeholder tracks \(done)/\(total)…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case let .ready(source, count, empty):
            VStack(alignment: .leading, spacing: 2) {
                Text("Music: \(source), \(count) tracks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !empty.isEmpty {
                    Text("No tracks for \(empty.map(\.rawValue).joined(separator: ", ")): the nearest moods stand in.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        case let .failed(message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

struct StoryCard: View {
    @ObservedObject var session: DemoSession

    var body: some View {
        let sentence = session.currentSentence
        let chapter = session.story.chapters[sentence.chapter]
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if sentence.globalIndex > 0 {
                    Text(session.story.sentences[sentence.globalIndex - 1].text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(sentence.text)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    MoodChip(label: "Text", mood: sentence.mood)
                    MoodChip(label: "Music", mood: session.snapshot?.musicMood)
                    Spacer()
                    Text("\(sentence.globalIndex + 1)/\(session.story.sentences.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("The text label is the story's hand-written mood. The music only ever hears readings of text already narrated, so it follows a little behind.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("\(session.story.title): \(chapter.title)", systemImage: "book")
        }
    }
}

struct TransportCard: View {
    @ObservedObject var session: DemoSession

    var body: some View {
        GroupBox {
            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    Button { session.previousChapter() } label: { Image(systemName: "backward.end.fill") }
                    Button { session.skip(seconds: -30) } label: { Image(systemName: "gobackward.30") }
                    Button { session.togglePlay() } label: {
                        Image(systemName: session.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                    }
                    Button { session.skip(seconds: 30) } label: { Image(systemName: "goforward.30") }
                    Button { session.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                }
                .font(.title2)
                .buttonStyle(.borderless)
                HStack(spacing: 12) {
                    Button("Sleep in 15 s") { session.sleep(after: 15) }
                    Button(session.isBookOpen ? "Close book" : "Open book") { session.toggleBook() }
                    Menu("Chapter") {
                        ForEach(Array(session.story.chapters.enumerated()), id: \.offset) { index, chapter in
                            Button("\(index + 1). \(chapter.title)") { session.jump(toChapter: index) }
                        }
                    }
                    .fixedSize()
                }
                .font(.callout)
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        } label: {
            Label("Narrator", systemImage: "waveform")
        }
    }
}

struct MusicCard: View {
    let snapshot: PlayerSnapshot?

    var body: some View {
        GroupBox {
            if let snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        MoodChip(label: "Playing", mood: snapshot.musicMood)
                        if let pending = snapshot.pendingMood {
                            MoodChip(label: "Next", mood: pending)
                        }
                        Spacer()
                        Text(snapshot.engineRunning ? "engine on" : "engine off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.decks, id: \.deck) { deck in
                        DeckRow(deck: deck, active: deck.deck == snapshot.activeDeck)
                    }
                    HStack(spacing: 16) {
                        Meter(label: "Fade", value: snapshot.transportGain)
                        Text(String(format: "Lift %+.1f dB", snapshot.duckOffsetDB))
                            .font(.caption.monospacedDigit())
                        if snapshot.routeMuted {
                            Text("muted on this output").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    if let error = snapshot.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            } else {
                Text("Waiting for the music library…").foregroundStyle(.secondary)
            }
        } label: {
            Label("Music", systemImage: "music.note")
        }
    }
}

struct DeckRow: View {
    let deck: PlayerSnapshot.DeckState
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(deck.deck.description)
                .font(.caption.bold())
                .frame(width: 18)
                .foregroundStyle(active ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.trackID ?? "empty")
                    .font(.caption)
                    .lineLimit(1)
                if let position = deck.position, deck.duration > 0 {
                    ProgressView(value: min(position, deck.duration), total: deck.duration)
                        .tint(color(for: deck.mood))
                }
            }
            Meter(label: "", value: deck.crossfadeGain)
                .frame(width: 70)
        }
        .opacity(deck.isRunning ? 1 : 0.5)
    }
}

struct DirectorCard: View {
    let snapshot: PlayerSnapshot?
    let lastReading: MoodObservation?

    var body: some View {
        GroupBox {
            if let director = snapshot?.director {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(MoodBucket.allCases, id: \.self) { bucket in
                        let share = director.shares[bucket] ?? 0
                        HStack(spacing: 8) {
                            Text(bucket.rawValue.capitalized)
                                .font(.caption)
                                .frame(width: 84, alignment: .leading)
                                .fontWeight(bucket == director.currentBucket ? .bold : .regular)
                            Bar(value: share, color: color(for: bucket))
                            Text(String(format: "%.0f%%", share * 100))
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    Divider()
                    Text(phaseText(director))
                        .font(.caption)
                    if let pending = director.pendingBucket {
                        Text("Waiting to confirm \(pending.rawValue): \(director.pendingCount) reading(s)")
                            .font(.caption)
                    }
                    Text(director.dwellWaived || director.dwellRemaining <= 0
                         ? "Free to change"
                         : String(format: "Holding for %.0f s more (minimum dwell)", director.dwellRemaining))
                        .font(.caption)
                    if let reading = lastReading {
                        Text("Last reading: \(reading.reading.bucket.rawValue), \(Int(reading.reading.confidence * 100))% (\(reading.trigger.rawValue), sentence \(reading.globalSentenceIndex + 1))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let decision = director.lastDecision {
                        Text("Last change: \(decision.previous.rawValue) → \(decision.bucket.rawValue) (\(decision.reason.rawValue))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let ignored = director.ignoredCounts.filter { $0.value > 0 }
                    if !ignored.isEmpty {
                        Text("Ignored: " + ignored.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No readings yet").foregroundStyle(.secondary)
            }
        } label: {
            Label("Director", systemImage: "slider.horizontal.3")
        }
    }

    private func phaseText(_ director: DirectorSnapshot) -> String {
        switch director.phase {
        case .awaitingFirstReading: return "Waiting for the first reading"
        case .awaitingSeekReading: return "Waiting for a reading of the new place"
        case .following: return "Following the story"
        }
    }
}

struct SettingsCard: View {
    @ObservedObject var session: DemoSession
    @Binding var choosingFolder: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Music", isOn: $session.musicEnabled)
                Toggle("Read the story aloud", isOn: $session.speakAloud)
                Toggle("Follow the book's mood track (off: live readings)", isOn: $session.followMoodTrack)
                Toggle("Fast demo timings (12 s smoothing, 20 s dwell, 15 s between track turns)", isOn: $session.fastTimings)
                Toggle("Music off in the car (CarPlay)", isOn: $session.muteInCar)
                LabeledSlider(title: "Bed under the voice", value: $session.bedLevelDB, range: -24...(-6), format: "%.0f dB")
                LabeledSlider(title: "Lift in silences", value: $session.gapLiftDB, range: 0...8, format: "+%.0f dB")
                LabeledSlider(title: "Music volume", value: $session.musicVolume, range: 0...1, format: "%.2f")
                LabeledSlider(title: "Narrator speed", value: $session.narratorRate, range: 0.75...2, format: "%.2fx")
                LabeledSlider(title: "Reading noise (live)", value: $session.readingNoise, range: 0...0.5, format: "%.2f")
                HStack {
                    Button("Choose music folder…") { choosingFolder = true }
                    Button("Use placeholders") { session.preparePlaceholders() }
                }
                .buttonStyle(.bordered)
                Text("A music folder holds one subfolder per mood (Calm, Cozy, Playful, Hopeful, Melancholy, Mysterious, Tense, Somber) or a library.json.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
}

struct LogCard: View {
    let lines: [DemoSession.LogLine]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines.prefix(40)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line.time).foregroundStyle(.secondary)
                        Text(line.text)
                    }
                    .font(.caption.monospaced())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Log", systemImage: "list.bullet")
        }
    }
}

// MARK: - Pieces

struct MoodChip: View {
    let label: String
    let mood: MoodBucket?

    var body: some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(mood?.rawValue.capitalized ?? "—").bold()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color(for: mood).opacity(0.22)))
    }
}

struct Bar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 8)
    }
}

struct Meter: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                Text(label).font(.caption)
            }
            Bar(value: value, color: .accentColor)
                .frame(minWidth: 50)
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(String(format: format, value)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

func color(for mood: MoodBucket?) -> Color {
    switch mood {
    case .calm?: return .teal
    case .cozy?: return .orange
    case .playful?: return .yellow
    case .hopeful?: return .green
    case .melancholy?: return .indigo
    case .mysterious?: return .purple
    case .tense?: return .red
    case .somber?: return .gray
    case .romantic?: return .pink
    case .dreamy?: return .cyan
    case .adventurous?: return .brown
    case nil: return .secondary
    }
}
#endif
