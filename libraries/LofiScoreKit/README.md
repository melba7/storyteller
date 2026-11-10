# LofiScoreKit

Spoiler-safe atmosphere sounds under Storyteller's narration: the sounds of the
scene being narrated, scored ahead of time from what has already been read,
never from what comes next.

How it works, in short: a Mac (or any machine with the tools) reads a book's
read-aloud EPUB sentence by sentence and asks Claude, every few hundred words,
where the story is now, what that place is like and what it sounds like, from a
catalogue of 48 sound families and 360 more specific kinds. Each answer sees only
the text up to its own sentence and the places met before it. The answers become
an *atmosphere track* that travels with the book; the phone plays the track
under the narrator, keeps each place's recording across visits, lets the weather
follow the story indoors, pauses the narrator for a moment where a scene arrives
or falls silent, and plays a knock or a clap of thunder on the sentence that
says so.

- **Sound side** (the scene scorer, the track builder, the layered player, the
  app host): `LofiAudioCore`, `LofiAtmosphere`, `LofiScoreHost`, and the
  `lofi-atmosphere` tool. See [Docs/Atmosphere.md](Docs/Atmosphere.md).
- **Text side** (sentence windows that never look ahead, and the mood detection
  the shelved music used): `LofiText`, `LofiMood`, `lofi-eval`, `lofi-train`.
  See [Docs/MoodDetection.md](Docs/MoodDetection.md).
- **Shared:** `LofiScoreCore` holds the value types both sides use.
- **Measuring the scorer:** `Tools/atmosphere/eval/` holds a test set of
  passages from public-domain books, each labelled by hand with the place,
  setting, sounds, state, scene start, transition and one-off sound the scorer
  should answer, and `lofi-atmosphere eval` scores a prompt against it check by
  check. See "Scoring accuracy" in `Docs/Atmosphere.md`.

The lofi music that played alongside (its director, two-deck player,
placeholder library, demo and library scripts) is shelved whole, not deleted:
[shelved/lofi-music/README.md](../../shelved/lofi-music/README.md) at the
repository root lists what it was and how to bring it back.

```sh
swift test --filter "LofiAtmosphereTests|LofiScoreHostTests"   # the atmosphere, off Apple platforms too
swift run -c release lofi-atmosphere track BOOK-DIR --book NAME --out NAME.atmosphere.json   # score a book
swift run -c release lofi-atmosphere show NAME.atmosphere.json --places                      # read a track
swift run -c release lofi-atmosphere eval Tools/atmosphere/eval/cases.jsonl --out results.jsonl   # measure the scorer
swift run -c release lofi-atmosphere catalog --out Tools/atmosphere/catalog.json             # after editing the catalogue
```

Scoring goes through the Claude plan by default (`LOFI_CLAUDE_VIA=plan`, Claude
Code signed in) or the API (`LOFI_CLAUDE_VIA=api` with `ANTHROPIC_API_KEY`).
`Tools/mac/` has the scripts that do all of this unattended on a Mac.

Audio never goes into git: this fork is public.
