// LOFI-FORK: the podcasts section's transcripts (see FORK.md).
//
// Thin wrappers over the native module's transcript functions. Not imported by any test,
// because the native module is not there; the rules are in transcripts.ts.
import { type SpokenHit, type TranscriptInfo, Podcasts } from "./index"

export async function listTranscripts(): Promise<TranscriptInfo[]> {
  return (await Podcasts?.listTranscripts()) ?? []
}

/** A finished transcript as JSON text, or null. */
export async function getTranscript(episodeId: string): Promise<string | null> {
  return (await Podcasts?.getTranscript(episodeId)) ?? null
}

/** The lines made so far of a transcript that is not finished, as JSON text, or null. */
export async function getPartialTranscript(
  episodeId: string,
): Promise<string | null> {
  return (await Podcasts?.getPartialTranscript(episodeId)) ?? null
}

/** Where the words are said in every transcribed episode (at most a few per episode). */
export async function searchTranscripts(query: string): Promise<SpokenHit[]> {
  return (await Podcasts?.searchTranscripts(query)) ?? []
}
