// LOFI-FORK: the podcasts section's voice boost and silence trimming (see FORK.md).
//
// The native call that reads the time silence trimming has saved. Where there is no native
// module it is 0. Not imported by any test.
import { Podcasts } from "./index"

/** Seconds of audio that silence trimming has cut so far. */
export async function getTrimSavings(): Promise<number> {
  return (await Podcasts?.getTrimSavings()) ?? 0
}
