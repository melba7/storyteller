// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).
import { blocksOf, readCues } from "./cues"
import { type TranscriptLine, TranscriptFormatError } from "./types"

/** Reads WebVTT: the header, NOTE, STYLE and REGION blocks are skipped; `<v Name>` is the speaker. */
export function parseVtt(text: string): TranscriptLine[] {
  const blocks = blocksOf(text)
  const header = blocks[0]?.[0] ?? ""
  if (!/^WEBVTT(?:[ \t]|$)/.test(header)) {
    throw new TranscriptFormatError("This isn't a WebVTT transcript.")
  }
  return readCues(
    blocks
      .slice(1)
      .filter(
        (block) => !/^(?:NOTE|STYLE|REGION)(?:[ \t]|$)/.test(block[0] ?? ""),
      ),
  )
}
