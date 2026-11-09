# Mood labelling guidelines

These are the rules for every label in this folder, whoever writes it (Claude
for the training set, Mo for the gold set and the spot-checks). They match the
bucket definitions in `Sources/LofiMood/Prompt/MoodPrompt.swift`, so the
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
| hopeful | uplifting: relief, triumph, reunion, love declared, things turning out well |
| melancholy | sad and quiet: loss, longing, loneliness, regret, homesickness |
| mysterious | uncertain or eerie: secrets, puzzles, strange sights or sounds, something unexplained |
| tense | danger, conflict, fear, a chase, a fight, a bitter argument; urgent suspense |
| somber | grave and heavy: death, grief, funerals, solemn ritual, dread, despair |

Tie-breaks:

- When nothing in particular is going on, the answer is **calm**. Most of a
  novel is calm; that is fine.
- calm vs cozy: cozy needs warmth or affection on the page, not just a quiet room.
- playful vs hopeful: playful is humour and banter; hopeful is uplift and relief.
- melancholy vs somber: melancholy is quiet sadness; somber is weight, death or dread.
- mysterious vs tense: mysterious is not knowing; tense is danger happening now.
- A heated argument with real stakes is tense; mild disagreement or gossip is calm or playful.
- If the window ends on a chapter heading, label the mood the previous scene ended on.
