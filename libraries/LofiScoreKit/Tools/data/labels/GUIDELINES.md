# Mood labelling guidelines

These are the rules for every label in this folder, whoever writes it (Claude
for the training set, Mo for the gold set and the spot-checks). They match the
bucket definitions in `Sources/LofiMood/Prompt/MoodPrompt.swift` and
`Sources/LofiMood/Claude/ClaudeMoodPrompt.swift`, so the
classifier, the language-model engines and the people labelling all answer
the same question.

**The question:** what music fits the story *at the final sentences* of the
window, the part the listener is hearing now? Earlier sentences are context.

**Judge only the words shown.** Do not use anything you know about the book,
its author or its plot, and never label for what is about to happen.

| Bucket | Use when the final sentences are... |
| --- | --- |
| calm | quiet, settled or reflective; ordinary talk, travel, description, exposition; nothing at stake right now |
| cozy | warm and safe: home, food, firesides, friendship, gentle affection |
| playful | light, funny, teasing or mischievous; lively banter, comic mishaps |
| hopeful | uplifting: relief, triumph, reunion, things turning out well |
| melancholy | sad and quiet: loss, longing, loneliness, regret, homesickness |
| mysterious | uncertain or eerie: secrets, puzzles, strange sights or sounds, something unexplained |
| tense | danger, conflict, fear, a chase, a fight, a bitter argument; urgent suspense |
| somber | grave and heavy: death, grief, funerals, solemn ritual, dread, despair |
| romantic | love between people: courtship, a kiss, tenderness between lovers, love declared, a wedding |
| dreamy | wonder and enchantment: magic, marvels, dreams and reveries, beautiful strange sights; nothing threatening |
| adventurous | bold forward motion, excitement more than fear: setting out, exploring, sailing or riding into the unknown, a daring feat going well, discovery |

Tie-breaks:

- When nothing in particular is going on, the answer is **calm**. Most of a
  novel is calm; that is fine.
- calm vs cozy: cozy needs warmth or affection on the page, not just a quiet room.
- playful vs hopeful: playful is humour and banter; hopeful is uplift and relief.
- melancholy vs somber: melancholy is quiet sadness; somber is weight, death or dread.
- mysterious vs tense: mysterious is not knowing; tense is danger happening now.
- A heated argument with real stakes is tense; mild disagreement or gossip is calm or playful.
- romantic vs cozy: romantic is love or attraction between two people; cozy is the warmth of home, family and friends.
- romantic vs hopeful: a kiss or a love declared is romantic; relief or triumph without romance is hopeful.
- Love lost or unreturned, mostly sad, is melancholy, not romantic.
- dreamy vs mysterious: dreamy is wonder and beauty; mysterious is not knowing, with unease.
- dreamy vs calm: dreamy needs magic, enchantment or awe on the page, not just a quiet scene.
- adventurous vs tense: adventurous is excitement and momentum; tense is fear with a real threat now.
- adventurous vs playful: playful is humour; adventurous is daring and discovery.
- Ordinary travel described without excitement is calm, not adventurous.
- If the window ends on a chapter heading, label the mood the previous scene ended on.

## Versions

- v1 (8 Nov 2026): the first eight moods.
- v2 (9 Nov 2026): adds romantic, dreamy and adventurous at Mo's request, and
  moves "love declared" from hopeful to romantic. The other definitions are
  unchanged. Labels made under v1 (`claude-v1.jsonl`, `claude-v2.jsonl`,
  `claude-rerun-80.jsonl`) never use the new moods; `claude-g2-*.jsonl` files
  are labelled under v2.
