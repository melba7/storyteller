// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).

/** One line of a transcript: seconds from the start of the audio. */
export type TranscriptLine = {
  start: number
  end: number
  /** Who speaks, kept from the line before when a line does not say. */
  speaker?: string
  text: string
}

/** Said when a transcript file cannot be read. The message is for the listener. */
export class TranscriptFormatError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "TranscriptFormatError"
  }
}
