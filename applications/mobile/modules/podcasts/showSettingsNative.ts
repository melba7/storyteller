// LOFI-FORK: the podcasts section's per-show settings (see FORK.md).
//
// The native call that saves every show's playback settings where the Swift player reads
// them, so the intro skip, the outro and the show's speed work with the screen locked. Where
// there is no native module nothing is written. Not imported by any test.
import { Podcasts } from "./index"

export async function writeShowSettings(json: string): Promise<void> {
  await Podcasts?.writeShowSettings(json)
}
