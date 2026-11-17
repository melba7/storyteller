// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).
//
// Adapted from Transcriptator's `timestamp.ts` (https://github.com/stevencrader/transcriptator),
// MIT License, Copyright (c) 2023 Steven Crader. The licence text is in FORK.md
// ("Third-party code"); the copyright and permission notice apply to this file.
//
// Changes: a plain function, no formatter, and a fraction like ".5" is half a second (the
// original reads it as 5 milliseconds).

/** [hours:][minutes:]seconds with an optional fraction after "." or ",". */
const TIMESTAMP = /^(?:(\d+):)?(?:(\d+):)?(\d+)(?:[,.](\d+))?$/

/**
 * Reads a time such as "01:02:03.500", "02:03,5", "93" or "93.25" as seconds. Returns null
 * for anything else.
 */
export function parseTimestamp(value: string): number | null {
  const match = TIMESTAMP.exec(value.trim())
  if (!match) return null
  const [, first, second, last, fraction] = match
  // "1:02" has one colon: the first group captured minutes' position, so shift it.
  const parts = second === undefined ? [undefined, first] : [first, second]
  const hours = Number(parts[0] ?? 0)
  const minutes = Number(parts[1] ?? 0)
  const seconds = Number(last)
  const part = fraction === undefined ? 0 : Number(`0.${fraction}`)
  return hours * 3600 + minutes * 60 + seconds + part
}
