import Foundation
import LofiScoreCore

/// Hand-written cue words for the lexicon baseline.
///
/// Each entry is a word or a stem ending in "*" (matching any word that starts
/// with it, at least four letters long). The lists are a baseline, not a model:
/// they exist so the eval has a floor, and so devices without Apple
/// Intelligence or the trained classifier still get a sensible guess.
enum MoodLexicon {
    static let cues: [MoodBucket: [String]] = [
        .calm: [
            "quiet*", "stillness", "gentl*", "soft*", "peace*", "calm*", "slow*", "rest*", "sleep*",
            "drows*", "drift*", "breeze", "meadow*", "lake", "pond", "afternoon", "stroll*", "wander*", "sat",
            "sitting", "read", "reading", "evening", "dusk", "sunlight", "sunshine", "clouds", "hush*", "serene",
            "tranquil*", "idle", "lazy", "leisure*", "pastur*", "fields", "birdsong", "murmur*", "ripple*",
        ],
        .cozy: [
            "warm*", "hearth*", "fireside", "fireplace", "tea", "teapot", "kettle", "blanket*", "cushion*",
            "kitchen*", "bread", "baking", "baked", "supper", "breakfast", "dinner", "cottage", "slipper*",
            "lamp*", "cat", "kitten*", "purr*", "pipe", "armchair*", "toast*", "cocoa", "knit*", "snug*",
            "cosy", "cozy", "comfort*", "home", "homely", "pudding*", "pie", "cake*", "jam", "butter*",
            "embrac*", "hug*", "cuddl*", "fond*", "affection*", "darling", "dear", "dearest", "nestl*",
            "candlelight", "parlour", "parlor", "christmas", "carol*",
        ],
        .playful: [
            "laugh*", "giggl*", "grin*", "joke*", "jest*", "teas*", "merr*", "mischie*", "jolly", "fun",
            "funny", "danc*", "skip*", "silly", "wink*", "chuckl*", "romp*", "game*", "prank*", "tickl*",
            "frolic*", "caper*", "clown*", "absurd*", "ridiculous*", "nonsense", "whimsic*", "delight*",
            "amus*", "comic*", "playful*", "cheek*", "impish", "sly", "banter*", "tumbl*", "hop", "hopped",
        ],
        .hopeful: [
            "hope*", "dawn*", "sunrise", "bright*", "joy*", "triumph*", "victor*", "freedom", "free", "smil*",
            "bless*", "promis*", "spring", "bloom*", "future", "dream*", "rescu*", "saved", "reunit*",
            "together", "courag*", "brave*", "glori*", "radian*", "rejoic*", "cheer*", "heal*", "renew*",
            "succeed*", "success*", "won", "win", "proud", "pride", "faith*", "wonder*", "marvel*", "glow*",
            "rainbow", "light", "relief", "relieved", "grateful", "gratitude",
        ],
        .melancholy: [
            "sad*", "sorrow*", "tears", "weep*", "wept", "lonel*", "alone", "miss", "missed", "longing",
            "regret*", "wistful*", "memor*", "rememb*", "lost", "farewell", "goodbye", "sigh*",
            "rain*", "autumn", "grief", "griev*", "heartache", "melanchol*", "pale", "faded", "fading",
            "empty", "emptiness", "forgot*", "abandon*", "parted", "parting", "ache*", "aching", "mourn*",
            "wither*", "gone", "homesick*", "solitude",
        ],
        .mysterious: [
            "strange*", "myster*", "secret*", "shadow*", "whisper*", "fog*", "mist*", "unknown", "hidden",
            "hide", "curious*", "odd", "puzzl*", "clue*", "silen*", "dim*", "ghost*", "phantom*", "figure",
            "creak*", "footstep*", "candle*", "midnight", "unseen", "vanish*", "riddle*", "inexplicab*",
            "uncann*", "peculiar*", "faint*", "glimmer*", "eerie", "weird*", "cipher*", "locked", "key",
            "corridor*", "cellar*", "attic*", "portrait*", "rumour*", "rumor*", "legend*", "spectr*",
            "apparition*", "lantern*", "veil*", "hooded", "cloak*", "stranger*",
        ],
        .tense: [
            "scream*", "shriek*", "blood*", "gun*", "pistol*", "rifle*", "knife", "knives", "sword*",
            "dagger*", "fight*", "fought", "attack*", "ran", "run", "running", "fled", "flee*", "chas*",
            "danger*", "fear*", "afraid", "terror*", "terrif*", "panic*", "struggl*", "shot", "shoot*",
            "crash*", "explo*", "grabb*", "seiz*", "shout*", "hurr*", "escap*", "trap*", "enem*", "kill*",
            "murder*", "wound*", "threat*", "pursu*", "battle*", "storm*", "thunder*", "flames", "burning",
            "trembl*", "shak*", "pound*", "gasp*", "desperat*", "frantic*", "suddenly", "alarm*", "beast*",
            "monster*", "wolf", "wolves", "snarl*", "growl*", "claw*", "fang*", "strangl*", "choke*",
        ],
        .somber: [
            "death", "dead", "die", "died", "dying", "grave*", "funeral*", "coffin*", "corpse*", "tomb*",
            "bury", "buried", "burial", "solemn*", "grim*", "doom*", "ruin*", "despair*", "bleak*", "war",
            "widow*", "orphan*", "toll*", "knell", "black", "darkness", "cold", "dread*", "fate", "fatal*",
            "perish*", "slain", "sacrific*", "suffer*", "agony", "misery", "miserable", "wretch*", "hopeless*",
            "condemn*", "execution*", "gallows", "cemetery", "churchyard", "requiem", "lament*", "mortal*",
        ],
    ]

    /// Words that pull valence up or down, used for the lexicon's own valence estimate.
    static let positive: [String] = [
        "good", "happy", "happi*", "love*", "lovel*", "kind*", "gentle", "smile*", "smiling", "laugh*",
        "joy*", "delight*", "pleas*", "beautif*", "sweet*", "warm*", "bright*", "hope*", "glad*", "friend*",
        "wonderful", "safe", "comfort*", "cheer*", "fine", "grand", "best", "better", "won", "free", "peace*",
    ]

    static let negative: [String] = [
        "bad", "sad*", "fear*", "afraid", "terr*", "horr*", "pain*", "hurt*", "cry", "cried", "weep*",
        "dead", "death", "die", "died", "kill*", "blood*", "hate*", "angry", "anger", "cruel*", "evil",
        "wicked", "dark*", "cold", "lost", "alone", "grief", "sorrow*", "misery", "wretch*", "ugly",
        "scream*", "despair*", "danger*", "worse", "worst", "poor", "sick*", "ill", "wound*", "never",
    ]

    /// High-energy words, used for the arousal estimate.
    static let energetic: [String] = [
        "ran", "run", "running", "rushed", "rush*", "shout*", "scream*", "crash*", "fight*", "leap*",
        "jump*", "dash*", "burst*", "slam*", "race*", "racing", "quick*", "sudden*", "fast", "faster",
        "seiz*", "grabb*", "struck", "strike", "hurr*", "storm*", "thunder*", "danc*", "laugh*", "shriek*",
    ]
}

/// Looks up words in cue lists, matching exact words and "stem*" prefixes.
struct CueMatcher {
    private var exact: [String: [Int]] = [:]
    private var stems: [String: [Int]] = [:]
    private var stemLengths: [Int] = []

    /// `lists[i]` is the cue list for category `i`.
    init(_ lists: [[String]]) {
        var lengths = Set<Int>()
        for (category, list) in lists.enumerated() {
            for raw in list {
                let cue = raw.lowercased()
                if cue.hasSuffix("*") {
                    let stem = String(cue.dropLast())
                    stems[stem, default: []].append(category)
                    lengths.insert(stem.count)
                } else {
                    exact[cue, default: []].append(category)
                }
            }
        }
        stemLengths = lengths.sorted(by: >)
    }

    /// Categories a lowercase word belongs to.
    func categories(of word: String) -> [Int] {
        var found = exact[word] ?? []
        if word.count >= 3 {
            for length in stemLengths where length <= word.count {
                if let hit = stems[String(word.prefix(length))] {
                    for category in hit where !found.contains(category) { found.append(category) }
                }
            }
        }
        return found
    }
}
