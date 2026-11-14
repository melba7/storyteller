// LOFI-FORK: the sound check's steps and results, apart from the screen
// (see FORK.md).
import type { LofiSoundCheckStop } from "./index"
import { soundList, soundName } from "./status"

export type SoundCheckAnswer =
  | "tooLoud"
  | "clear"
  | "faint"
  | "cantHear"
  | "wrongSound"

export const SOUND_CHECK_ANSWERS: { value: SoundCheckAnswer; label: string }[] =
  [
    { value: "tooLoud", label: "Too loud" },
    { value: "clear", label: "Clear" },
    { value: "faint", label: "Faint" },
    { value: "cantHear", label: "Can't hear" },
    { value: "wrongSound", label: "Wrong sound" },
  ]

/** How long each stop plays before the question, in milliseconds. */
export const SOUND_CHECK_LISTEN_MS = 20_000

export type SoundCheckSession = {
  stops: LofiSoundCheckStop[]
  /** One answer per stop answered so far, in order. */
  answers: SoundCheckAnswer[]
}

export function startSoundCheck(
  stops: LofiSoundCheckStop[],
): SoundCheckSession {
  return { stops, answers: [] }
}

export function currentStop(
  session: SoundCheckSession,
): LofiSoundCheckStop | null {
  return session.stops[session.answers.length] ?? null
}

export function isFinished(session: SoundCheckSession): boolean {
  return session.answers.length >= session.stops.length
}

/** Records the answer for the current stop and moves on to the next one. */
export function answerStop(
  session: SoundCheckSession,
  answer: SoundCheckAnswer,
): SoundCheckSession {
  if (isFinished(session)) return session
  return { ...session, answers: [...session.answers, answer] }
}

const KIND_TITLES: Record<string, string> = {
  quietRoom: "A quiet room",
  loud: "Something loud",
  outdoors: "Outdoors",
  water: "Water",
  weather: "Weather",
  travel: "Travel",
  oneOff: "A one-off sound",
  other: "Another scene",
}

/** "river.runningTap" → "running tap"; "roomTone" → "a quiet room". */
function soundKeyName(key: string): string {
  const [sound = key, variant] = key.split(".")
  return variant ? soundName(variant) : soundName(sound)
}

/** What the stop should sound like: "Water: running tap". */
export function stopLabel(stop: LofiSoundCheckStop): string {
  const title = KIND_TITLES[stop.kind] ?? "A scene"
  const place = stop.placeName ? ` (${stop.placeName})` : ""
  const sounds = soundList(stop.sounds.map(soundKeyName))
  return `${title}${place}: ${sounds.charAt(0).toLowerCase()}${sounds.slice(1)}`
}

export type SoundCheckContext = {
  book: string
  levelDB: number
  defaultLevelDB: number
  intensity: number
}

/** The answers as plain text, to paste into a chat. */
export function resultsText(
  session: SoundCheckSession,
  context: SoundCheckContext,
): string {
  const level = Math.round(context.levelDB)
  const isDefault = level === Math.round(context.defaultLevelDB)
  const lines = [
    `Sound check: ${context.book}`,
    `Sounds volume ${level} dB${isDefault ? " (default)" : ""}, how much is going on ${Math.round(context.intensity * 100)}%`,
  ]
  session.stops.forEach((stop, index) => {
    const answer = session.answers[index]
    const label =
      SOUND_CHECK_ANSWERS.find((a) => a.value === answer)?.label ??
      "not answered"
    const place = stop.placeName ? ` (${stop.placeName})` : ""
    lines.push(
      `${index + 1}. #${stop.globalIndex} ${stop.kind} ${stop.sounds.join(", ")}${place}: ${label}`,
    )
  })
  return lines.join("\n")
}

// The last results stay while the app runs, so closing the panel loses nothing.
let lastResults: string | null = null

export function rememberResults(text: string) {
  lastResults = text
}

export function rememberedResults(): string | null {
  return lastResults
}
