// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).
import { blocksOf, readCues } from "./cues"
import { type TranscriptLine, TranscriptFormatError } from "./types"

/** Reads SubRip: numbered cues of "start --> end" and text, with "," before the milliseconds. */
export function parseSrt(text: string): TranscriptLine[] {
  const blocks = blocksOf(text)
  if (!blocks.some((block) => block.some((line) => line.includes("-->")))) {
    throw new TranscriptFormatError("This isn't an SRT transcript.")
  }
  return readCues(blocks)
}
