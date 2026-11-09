import Foundation
import LofiScoreCore
import LofiText

/// The instructions and prompt shared by every language-model engine
/// (Apple's on-device model today; Private Cloud Compute or Claude later).
///
/// The wording does three jobs: it defines the eight buckets in a way that
/// separates neighbours, it tells the model to judge only the passage (no plot
/// knowledge, no guessing what happens next), and it pins the answer to one
/// parseable line.
public enum MoodPrompt {
    /// Bump when the wording changes; engines include it in their ids.
    public static let version = 2

    public static let instructions = """
        You choose background music for an audiobook. You will see the passage that has just \
        been read aloud, oldest sentence first. Decide the mood of the story at its final \
        sentences, because that is what the listener is hearing now.

        Judge only the words in the passage. Ignore anything you may know about this book, \
        its author or its plot, and never guess what happens next.

        Pick exactly one mood:
        calm: quiet, settled or reflective; nothing at stake right now
        cozy: warm and safe; home, food, friendship, gentle affection
        playful: light, funny, teasing or mischievous; lively banter
        hopeful: uplifting; relief, triumph, reunion, things turning out well
        melancholy: sad and quiet; loss, longing, loneliness, regret
        mysterious: uncertain or eerie; secrets, puzzles, something unexplained
        tense: danger, conflict, fear, a chase or a fight; urgent suspense
        somber: grave and heavy; death, grief, solemn ritual, dread

        Most of a novel is calm: ordinary conversation, travel, description, explanation. \
        Answer calm unless the final sentences clearly carry another mood. Choose tense only \
        for danger or conflict happening now, somber only for death, grief or dread, and \
        hopeful only for clear relief or happiness. Cozy needs warmth or affection on the \
        page; playful needs humour or teasing.

        Also rate valence from -1 (very unpleasant) to 1 (very pleasant), arousal from 0 \
        (still) to 1 (frantic), and your confidence from 0 to 1.

        Answer with one line in exactly this format and nothing else, putting one of the \
        eight mood words after bucket= and numbers after the other three:
        bucket=MOOD; valence=V; arousal=A; confidence=C
        """

    /// The prompt for one window, trimmed to its most recent `maxWords` words.
    public static func prompt(for window: CausalWindow, maxWords: Int = 400) -> String {
        let lines = window.recentLines(maxWords: maxWords)
        var passage = ""
        var previousChapter: Int? = nil
        for line in lines {
            if let previous = previousChapter {
                passage += previous == line.chapterOrdinal ? " " : "\n\n[new chapter]\n\n"
            }
            passage += line.text
            previousChapter = line.chapterOrdinal
        }
        if lines.count == 1, TextNormalizer.wordCount(passage) > maxWords {
            passage = TextNormalizer.suffix(passage, maxWords: maxWords)
        }
        return """
            Passage (the last sentence is being read aloud now):
            <<<
            \(passage)
            >>>
            Mood line:
            """
    }
}
