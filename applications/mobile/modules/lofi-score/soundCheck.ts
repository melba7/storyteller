// LOFI-FORK: the sound check's wording and results, apart from the screen
// (see FORK.md).
import type { LofiSoundCheckReading, LofiSoundCheckStop } from "./index"
import { soundList, soundName } from "./status"

export type SoundCheckAnswer =
  | "tooLoud"
  | "clear"
  | "faint"
  | "cantHear"
  | "wrongSound"

export const SOUND_CHECK_ANSWERS: {
  value: SoundCheckAnswer
  label: string
  hint: string
}[] = [
  { value: "tooLoud", label: "Too loud", hint: "gets in the way of the voice" },
  { value: "clear", label: "Clear", hint: "easy to hear with the voice" },
  { value: "faint", label: "Faint", hint: "only just there" },
  { value: "cantHear", label: "Can't hear", hint: "not there at all" },
  {
    value: "wrongSound",
    label: "Wrong sound",
    hint: "not what the story describes",
  },
]

/** How long each stop plays before the question, in milliseconds. */
export const SOUND_CHECK_LISTEN_MS = 20_000

/** What happened at one stop. */
export type SoundCheckResult = {
  answer?: SoundCheckAnswer
  /** The jump did not land on the stop, so it was skipped. */
  couldNotPlay?: boolean
  /** What played, read a few seconds into the stop. */
  reading?: LofiSoundCheckReading | null
}

/** The run's conditions, written once at the top of the results. */
export type SoundCheckContext = {
  book: string
  appVersion: string
  levelDB: number
  defaultLevelDB: number
  intensity: number
  defaultIntensity: number
  source: string
  playbackRate: number
  startedAt: string
}

/** "river.runningTap" → "running tap"; "roomTone" → "a quiet room". */
export function soundKeyName(key: string): string {
  const [sound = key, variant] = key.split(".")
  const raw = variant ?? sound
  return soundName(raw)
}

/** The sound to listen for: the stop's main sound. */
export function mainSoundName(stop: LofiSoundCheckStop): string {
  const main = stop.sounds[0]
  return main ? soundKeyName(main.key) : "the sounds"
}

/** "Listen for the waves (soft). Also there: wind." */
export function stopLabel(stop: LofiSoundCheckStop): string {
  const main = stop.sounds[0]
  const level = main?.level ? ` (${main.level})` : ""
  const place = stop.placeName ? ` in ${stop.placeName}` : ""
  const rest = stop.sounds.slice(1).map((sound) => soundKeyName(sound.key))
  const also =
    rest.length > 0 ? ` Also there: ${soundList(rest).toLowerCase()}.` : ""
  const what = stop.kind === "oneOff" ? "a one-off sound: " : ""
  return `Listen for ${what}${mainSoundName(stop)}${level}${place}.${also}`
}

/** "How did the waves come through under the voice?" */
export function stopQuestion(stop: LofiSoundCheckStop): string {
  return `How did ${mainSoundName(stop)} come through under the voice?`
}

function signed(value: number): string {
  const rounded = Math.round(value * 10) / 10
  return `${rounded > 0 ? "+" : ""}${rounded}`
}

function describeReading(reading: LofiSoundCheckReading | null | undefined) {
  if (!reading) return "    (nothing read)"
  const lines = reading.voices.map(
    (voice) =>
      `    ${voice.variant ? `${voice.sound}.${voice.variant}` : voice.sound} ${voice.level ?? "?"}: ${voice.recording}, gain ${signed(voice.gainDB)} dB${voice.atGainCap ? " (at the gain cap)" : ""}`,
  )
  if (reading.missingSounds.length > 0) {
    lines.push(`    missing: ${reading.missingSounds.join(", ")}`)
  }
  if (lines.length === 0) lines.push("    (no sounds playing)")
  return lines.join("\n")
}

/** The answers as plain text, to paste into a chat. */
export function resultsText(
  stops: LofiSoundCheckStop[],
  results: SoundCheckResult[],
  context: SoundCheckContext,
): string {
  const level = Math.round(context.levelDB)
  const levelDefault = level === Math.round(context.defaultLevelDB)
  const intensityDefault =
    Math.round(context.intensity * 20) ===
    Math.round(context.defaultIntensity * 20)
  const first = results.find((result) => result.reading)?.reading
  const lines = [
    `Sound check: ${context.book} (${context.startedAt})`,
    `App ${context.appVersion}, sounds ${context.source}, narration speed ${context.playbackRate}x`,
    `Sounds volume ${level} dB${levelDefault ? " (default)" : ""}, how much is going on ${Math.round(context.intensity * 100)}%${intensityDefault ? " (default)" : ""}`,
  ]
  if (first) {
    lines.push(
      `Output ${first.route}${first.routeMuted ? " (muted)" : ""}, bed ${first.bedLevelDB} dB under a ${first.voiceLoudnessLUFS} LUFS voice, one-offs ${first.oneShotsEnabled ? "on" : "off"}, pauses ${first.pausesEnabled ? "on" : "off"}`,
    )
  }
  stops.forEach((stop, index) => {
    const result = results[index]
    const answer = result?.couldNotPlay
      ? "could not play"
      : (SOUND_CHECK_ANSWERS.find((a) => a.value === result?.answer)?.label ??
        "not answered")
    const sounds = stop.sounds
      .map((sound) => (sound.level ? `${sound.key} ${sound.level}` : sound.key))
      .join(", ")
    const place = stop.placeName ? ` (${stop.placeName})` : ""
    lines.push(
      `${index + 1}. #${stop.globalIndex}-${stop.lastIndex} ${stop.kind} ${sounds}${place}: ${answer}`,
    )
    if (result && !result.couldNotPlay)
      lines.push(describeReading(result.reading))
  })
  return lines.join("\n")
}
