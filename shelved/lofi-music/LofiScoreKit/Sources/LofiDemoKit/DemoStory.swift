import Foundation
import LofiScoreCore

/// One sentence of the demo story, with the mood a careful reader would give it.
public struct DemoSentence: Sendable, Hashable, Identifiable {
    public let globalIndex: Int
    public let chapter: Int
    public let indexInChapter: Int
    public let text: String
    /// The hand-written mood label: the "truth" the scripted mood source reads from.
    public let mood: MoodBucket
    /// The last sentence of a paragraph is followed by a longer pause.
    public let endsParagraph: Bool

    public var id: Int { globalIndex }

    public var wordCount: Int {
        text.split(whereSeparator: { $0 == " " }).count
    }
}

public struct DemoChapter: Sendable, Hashable {
    public let title: String
    /// Global index of the chapter's first sentence.
    public let firstIndex: Int
    public let count: Int

    public var range: Range<Int> { firstIndex..<(firstIndex + count) }
}

/// A short original story whose mood moves through every bucket, so the demo shows
/// every kind of change: gentle drifts, a sudden turn, a chapter boundary and an ending.
public struct DemoStory: Sendable {
    public let title: String
    public let chapters: [DemoChapter]
    public let sentences: [DemoSentence]

    /// Builds a story from chapters of paragraphs; each paragraph has one mood.
    public init(title: String, chapters chapterSource: [(title: String, paragraphs: [(MoodBucket, [String])])]) {
        self.title = title
        var builtChapters: [DemoChapter] = []
        var builtSentences: [DemoSentence] = []
        for (chapterIndex, chapter) in chapterSource.enumerated() {
            let first = builtSentences.count
            var inChapter = 0
            for (mood, lines) in chapter.paragraphs {
                for (lineIndex, line) in lines.enumerated() {
                    builtSentences.append(DemoSentence(
                        globalIndex: builtSentences.count,
                        chapter: chapterIndex,
                        indexInChapter: inChapter,
                        text: line,
                        mood: mood,
                        endsParagraph: lineIndex == lines.count - 1
                    ))
                    inChapter += 1
                }
            }
            builtChapters.append(DemoChapter(title: chapter.title, firstIndex: first, count: inChapter))
        }
        self.chapters = builtChapters
        sentences = builtSentences
    }

    public func chapter(containing index: Int) -> DemoChapter {
        chapters[sentences[index].chapter]
    }

    /// "The Green Lantern": written for this demo.
    public static let greenLantern = DemoStory(title: "The Green Lantern", chapters: [
        ("The Lantern Shop", [
            (.calm, [
                "The harbour was still in the hour before the fishing boats came home.",
                "Mara unlocked the lantern shop and let the cool air in.",
                "Gulls drifted over the water without a sound.",
                "She wiped the counter slowly, the way her grandfather used to.",
                "Rows of brass lanterns caught the first grey light.",
                "Nothing in the town was in a hurry yet.",
            ]),
            (.cozy, [
                "By nine the kettle was singing on the little stove in the back.",
                "Old Mr. Pell came in from the drizzle and stamped his boots on the mat.",
                "He always asked for the same thing, a wick for a lamp he never seemed to light.",
                "Mara poured him tea in the chipped blue cup he liked.",
                "They sat by the window and watched the rain bead on the glass.",
                "The shop smelled of oil, wool and toast.",
            ]),
            (.playful, [
                "Then the bell over the door jangled twice, much too loudly.",
                "A small dog shot in, skidded on the wet floorboards, and crashed into a basket of candles.",
                "Candles rolled everywhere, and Mr. Pell lifted his feet like a startled heron.",
                "The dog's owner, a breathless boy with one sock showing, apologised four times in one sentence.",
                "Mara laughed so hard she had to sit down on the step ladder.",
                "The dog, entirely pleased with itself, chose a candle to carry home.",
            ]),
        ]),
        ("The Letter", [
            (.hopeful, [
                "In the afternoon the clouds broke and the sun came out over the quay.",
                "The postman brought a letter with a stamp Mara had never seen.",
                "It was from a museum across the sea that wanted to buy one of her lanterns.",
                "For the first time in months, she let herself imagine the shop full again.",
                "She read the letter twice, then once more out loud to the empty room.",
                "Outside, the boats were coming in with their sails turned gold.",
            ]),
            (.mysterious, [
                "At the bottom of the envelope was a second page, folded very small.",
                "It held no greeting, only a drawing of the pier and a mark beneath it.",
                "Beside the mark someone had written her grandfather's initials.",
                "Mara had never heard of anything beneath the pier but water and stones.",
            ]),
            (.adventurous, [
                "She folded the drawing into her coat, took the smallest lantern from the window and locked the shop behind her.",
                "The wind was at her back as she strode out along the sea wall, past the nets and the drying sails.",
                "She took the cliff steps two at a time, the lantern swinging and her scarf streaming out behind her.",
                "From the top she could see the whole curve of the bay and the long dark line of the pier.",
                "Whatever her grandfather had hidden down there, she meant to find it before the tide turned.",
            ]),
            (.mysterious, [
                "At the end of the boards she stopped and listened.",
                "Under the slap of the tide there was a faint, hollow knocking.",
                "A narrow hatch, crusted with salt, lay half hidden under a coil of rope.",
            ]),
            (.tense, [
                "The hatch groaned as she pulled it open.",
                "A ladder dropped into darkness, its rungs slick and cold.",
                "Halfway down, the lantern in her hand flickered and nearly went out.",
                "Somewhere below, water was rising fast through the gaps in the stone.",
                "She heard the hatch above her slam shut.",
                "Mara pressed her back to the wall and held her breath.",
                "Footsteps crossed the boards overhead, stopped, and walked away.",
            ]),
        ]),
        ("Below the Pier", [
            (.tense, [
                "The tide reached her ankles, then her knees.",
                "She pushed through a gap in the old brickwork and found a passage sloping upward.",
                "Her light caught a door with an iron ring, and she hauled on it with both hands.",
                "It gave all at once, and she fell through into a dry, silent room.",
                "Behind her the water roared through the passage and then, slowly, settled.",
            ]),
            (.somber, [
                "The room had been a workshop once.",
                "Tools lay where they had been set down long ago, furred with dust.",
                "On the bench stood a lantern with a cracked green lens.",
                "Next to it was a list of names, the crew of a boat that never came back.",
                "Her grandfather's name was the last one, written in another hand.",
                "Mara stood very still for a long time.",
            ]),
            (.melancholy, [
                "She remembered him whistling in the shop, out of tune and happy.",
                "She remembered the winter he stopped whistling.",
                "He had never told her about this room, or about the boat.",
                "Perhaps he had kept the lantern lit down here for them, every night, alone.",
                "She wiped the green lens with her sleeve.",
                "It was the only one of his lanterns she had never seen.",
            ]),
            (.dreamy, [
                "She struck a match and lit it.",
                "Green light spilled across the walls, slow and rippling, as if the whole room had sunk beneath the sea.",
                "Shapes swam in it: boats and stars, and the curve of the bay drawn in light across the ceiling.",
                "For a while she seemed to float among them, weightless, a long way from anything sad.",
                "It was the most beautiful thing she had ever seen.",
            ]),
        ]),
        ("Morning Tide", [
            (.melancholy, [
                "She sat with it until the tide went out.",
                "Pale light came through a grate high in the wall.",
                "Her clothes were stiff with salt and her hands ached.",
                "She did not want to leave him there.",
            ]),
            (.hopeful, [
                "Then she noticed the grate was a door, and the door opened onto the beach.",
                "She stepped out into a wide, bright morning.",
                "The boy with the dog was running along the sand, waving both arms.",
                "Behind him came Mr. Pell, and half the harbour with him.",
                "They had seen the hatch, and they had been searching all night.",
                "Mara held up the green lantern so they could see it.",
            ]),
            (.romantic, [
                "Tomas, the ferryman, reached her first and wrapped his coat around her shoulders.",
                "He had walked her home from school once, years ago, and had never quite stopped looking at her that way.",
                "His hand stayed on her arm a moment longer than it needed to.",
                "She leaned against him and let herself be held.",
                "Neither of them said anything, and neither of them needed to.",
            ]),
            (.cozy, [
                "Back at the shop, someone lit the stove and someone else found biscuits.",
                "Mr. Pell finally lit the lamp he had been buying wicks for all year.",
                "The dog fell asleep on her feet.",
                "She told them about the room and the list and the cracked green lens.",
                "Nobody hurried to leave.",
            ]),
            (.calm, [
                "That evening she wrote back to the museum.",
                "She would send them a lantern, she said, but not that one.",
                "The green lantern went in the window, facing the sea.",
                "When the boats came home that night, it was lit.",
                "The harbour was still, and the light lay quietly on the water.",
            ]),
        ]),
    ])
}
