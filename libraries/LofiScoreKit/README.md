# LofiScoreKit

Spoiler-safe, tone-matched lofi under Storyteller's narration. The music follows
the mood of what has already been narrated, never what comes next.

- **Text side** (mood detection): `LofiText`, `LofiMood`, `lofi-eval`, `lofi-train`.
  See [Docs/MoodDetection.md](Docs/MoodDetection.md).
- **Music side** (director, audio engine, placeholder library, demo):
  `LofiDirector`, `LofiAudio`, `LofiPlaceholders`, `LofiDemoKit`, `lofi-replay`,
  `lofi-placeholders`, `lofi-demo`. See [Docs/MusicEngine.md](Docs/MusicEngine.md).
- **Shared:** `LofiScoreCore` holds the value types both sides use
  (`MoodBucket`, `MoodReading`, `MoodObservation`).

```sh
swift test                                  # everything that runs off Apple platforms too
swift run lofi-replay --synthetic           # director on synthetic 10-hour books
swift run -c release lofi-placeholders      # synthesise the placeholder music
swift run -c release lofi-demo              # the demo, on a Mac
open Demo/LofiScoreDemo.xcodeproj           # the demo, on iPhone
```

Music never goes into git: this fork is public.
