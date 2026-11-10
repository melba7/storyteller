import Foundation
import LofiScoreCore

/// Settles a track's readings into scene-length moods.
///
/// A track has a reading every ~250 words plus the probes that pin changes
/// down, and neighbouring readings often name different moods that both suit
/// the scene (tense, then mysterious with tense listed as also fitting, then
/// tense again). The director follows every turn of a track, so played as it
/// is, the first real track (a 13.5-hour book) would have changed the music
/// 24 times an hour, holding a mood for a median of 85 seconds.
///
/// Settling cuts the book into scenes instead: the cheapest way to give every
/// entry a mood, where a sentence of narration costs nothing on the reading's
/// own mood, `alsoCost` on a mood the reading lists as also fitting (prompt
/// v3's `also`), up to 1 on any other mood (less when the two are close on
/// the valence/arousal map), and every change of mood costs `changeCost`
/// sentences. So a turn is followed only when the new mood fits better for
/// about that long. With the defaults the same book changes about 6 times an
/// hour, holds a mood for a median of 6 to 7 minutes, and is on a mood its
/// reading lists 95% of the time (Docs/MoodDetection.md has the table).
///
/// Spoiler safety: a scene may only start on an entry whose own mood it is,
/// and every entry was judged from the text up to its own sentence. So the
/// music never turns to a mood before the narrated text itself reads as that
/// mood. What does use the rest of the track is which turns are followed: a
/// mood that passes again within a minute or so is left out. A change heard
/// during playback therefore tells the listener that the new mood lasts a
/// while, and nothing about what happens.
public struct MoodSettling: Sendable, Hashable, Codable {
    /// What one change of music costs, in sentences of narration on a mood
    /// that does not fit. 9 sentences is about a minute.
    public var changeCost: Double
    /// What a sentence costs on a mood the reading only lists as also fitting.
    public var alsoCost: Double
    /// How many sentences the last entry is taken to cover.
    public var tailSentences: Double

    public init(changeCost: Double = 9, alsoCost: Double = 0.25, tailSentences: Double = 15) {
        self.changeCost = max(0, changeCost)
        self.alsoCost = min(1, max(0, alsoCost))
        self.tailSentences = max(1, tailSentences)
    }

    /// The settings the app and the track builder use.
    public static let standard = MoodSettling()

    /// A reading lists `mood` as also fitting when its score is at least this
    /// share of the best mood's score. Claude's `also` moods get half the best
    /// mood's score; a classifier's long tail of small scores does not count.
    static let alsoShare = 0.4

    /// The settled mood for each entry, in the entries' order.
    public func moods(for entries: [MoodTrack.Entry]) -> [MoodBucket] {
        guard let first = entries.first else { return [] }
        let all = MoodBucket.allCases
        let count = all.count

        func sentences(_ i: Int) -> Double {
            i + 1 < entries.count ? Double(max(0, entries[i + 1].globalIndex - entries[i].globalIndex)) : tailSentences
        }
        func cost(_ mood: MoodBucket, _ reading: MoodReading) -> Double {
            if mood == reading.bucket { return 0 }
            if Self.lists(reading, mood) { return alsoCost }
            return 0.6 + 0.4 * min(1, mood.anchor.distance(to: reading.bucket.anchor))
        }

        // best[m]: the cheapest cut of the entries so far that ends on mood m.
        var best = [Double](repeating: .infinity, count: count)
        // previous[i][m]: the mood before entry i on that cut.
        var previous = [[Int]](repeating: [Int](repeating: 0, count: count), count: entries.count)
        for (m, mood) in all.enumerated() where mood == first.reading.bucket {
            best[m] = sentences(0) * cost(mood, first.reading)
            previous[0][m] = m
        }
        for i in 1..<entries.count {
            let reading = entries[i].reading
            let length = sentences(i)
            // The first of the cheapest, so ties always go the same way.
            var cheapest = 0
            for m in 1..<count where best[m] < best[cheapest] { cheapest = m }
            var next = [Double](repeating: .infinity, count: count)
            for (m, mood) in all.enumerated() {
                let stay = best[m]
                // A scene only starts on an entry whose own mood it is.
                let turn = mood == reading.bucket && m != cheapest ? best[cheapest] + changeCost : .infinity
                if turn < stay {
                    next[m] = turn
                    previous[i][m] = cheapest
                } else {
                    next[m] = stay
                    previous[i][m] = m
                }
                next[m] += length * cost(mood, reading)
            }
            best = next
        }
        var last = 0
        for m in 1..<count where best[m] < best[last] { last = m }
        var moods = [MoodBucket](repeating: first.reading.bucket, count: entries.count)
        var m = last
        for i in stride(from: entries.count - 1, through: 0, by: -1) {
            moods[i] = all[m]
            m = previous[i][m]
        }
        return moods
    }

    /// The scenes in `entries`: where each starts (an index into `entries`)
    /// and its mood.
    public func scenes(in entries: [MoodTrack.Entry]) -> [(start: Int, mood: MoodBucket)] {
        var scenes: [(start: Int, mood: MoodBucket)] = []
        for (i, mood) in moods(for: entries).enumerated() where scenes.last?.mood != mood {
            scenes.append((i, mood))
        }
        return scenes
    }

    /// True when the reading names `mood` as its own or as also fitting.
    static func lists(_ reading: MoodReading, _ mood: MoodBucket) -> Bool {
        if mood == reading.bucket { return true }
        guard let scores = reading.scores, let score = scores[mood], score > 0 else { return false }
        let top = scores[reading.bucket] ?? scores.values.max() ?? 0
        return top > 0 && score >= alsoShare * top
    }
}
