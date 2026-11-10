# LofiScoreKit

Spoiler-safe atmosphere sounds under Storyteller's narration: the sounds of the
scene being narrated, scored ahead of time from what has already been read,
never from what comes next.

- **Text side** (mood detection): `LofiText`, `LofiMood`, `lofi-eval`, `lofi-train`.
  See [Docs/MoodDetection.md](Docs/MoodDetection.md).
- **Sound side** (the scene scorer, the layered player, the app host):
  `LofiAudioCore`, `LofiAtmosphere`, `lofi-atmosphere`, `LofiScoreHost`.
  See [Docs/Atmosphere.md](Docs/Atmosphere.md).
- **Shared:** `LofiScoreCore` holds the value types both sides use
  (`MoodBucket`, `MoodReading`, `MoodObservation`).

The lofi music that played alongside (its director, two-deck player,
placeholder library, demo and library scripts) is shelved whole, not deleted:
[shelved/lofi-music/README.md](../../shelved/lofi-music/README.md) at the
repository root lists what it was and how to bring it back.

```sh
swift test                                  # everything that runs off Apple platforms too
swift run -c release lofi-atmosphere        # score a book's atmosphere, show a track, synthesise stand-ins
```

Audio never goes into git: this fork is public.
