// LOFI-FORK: the podcasts section's voice boost and silence trimming (see FORK.md).
//
// The choices and their words. The sound itself is made in Swift (PodcastPlayback's
// BoostStrength and TrimStrength); these must match the names there.

export const BOOST_CHOICES = ["off", "low", "medium", "high"] as const
export type BoostStrength = (typeof BOOST_CHOICES)[number]

export const TRIM_CHOICES = ["off", "mild", "medium", "strong"] as const
export type TrimStrength = (typeof TRIM_CHOICES)[number]

/** A stored value, or "off" when it is not one of the choices. */
export function parseBoost(value: unknown): BoostStrength {
  return BOOST_CHOICES.find((choice) => choice === value) ?? "off"
}

export function parseTrim(value: unknown): TrimStrength {
  return TRIM_CHOICES.find((choice) => choice === value) ?? "off"
}

/** A show's own choice: null (follow the main setting) when it has none. */
export function parseShowBoost(value: unknown): BoostStrength | null {
  return BOOST_CHOICES.find((choice) => choice === value) ?? null
}

export function parseShowTrim(value: unknown): TrimStrength | null {
  return TRIM_CHOICES.find((choice) => choice === value) ?? null
}

function capital(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1)
}

export function boostLabel(value: BoostStrength): string {
  return capital(value)
}

export function trimLabel(value: TrimStrength): string {
  return capital(value)
}

/** What each choice does, in plain words, for the line under the setting. */
export const BOOST_BODY =
  "Makes quiet voices louder and keeps loud parts from clipping. Downloaded episodes only."
export const TRIM_BODY =
  "Cuts the long quiet gaps. Mild trims gaps over 1 second, Strong over 0.4. Downloaded episodes only."

/** "1 h 5 min saved", "40 s saved", for the time trimming has saved. */
export function savedLabel(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 1) return "Nothing saved yet"
  const total = Math.round(seconds)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  if (hours > 0) return `${hours} h ${minutes} min saved`
  if (minutes > 0) return `${minutes} min saved`
  return `${total} s saved`
}
