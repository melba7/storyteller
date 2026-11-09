// LOFI-FORK: wording for the lofi music's state (see FORK.md).
import type { LofiMusicStatus } from "./index"

/** "calm" → "Calm", as the music library's folders are named. */
export function moodName(mood: string) {
  return mood.charAt(0).toUpperCase() + mood.slice(1)
}

/** One line on what the music is doing, for the player's music panel. */
export function describeMusic(status: LofiMusicStatus): string {
  if (!status.enabled) return "Music is off"
  if (status.library.preparing) return "Getting the music ready…"
  if (status.library.source === "none") {
    return "No music yet. Import a music folder in Settings."
  }
  const book = status.book
  if (!book) return "Plays when you listen to a readaloud book"
  switch (book.text) {
    case "off":
    case "waiting":
    case "loading":
      return "Reading the book…"
    case "unavailable":
      return "This book has no text for the music to follow"
    case "ready":
      break
  }
  if (status.playback.routeMuted) return "Off in the car"
  if (!status.playback.narrating) return "Plays with the narration"
  if (status.playback.musicMood) {
    return `Playing ${status.playback.musicMood} music`
  }
  return "Starting…"
}

/** "heavyRain" → "heavy rain", with a few sounds named for what you hear. */
export function soundName(sound: string): string {
  const named: Record<string, string> = {
    rainIndoors: "rain on the windows",
    seaShore: "waves",
    openSea: "the open sea",
    oldTown: "an old town",
    clock: "a ticking clock",
    fireplace: "a fire",
    campfire: "a campfire",
  }
  return named[sound] ?? sound.replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
}

/** "rain, wind and a fire", capitalised. */
export function soundList(sounds: string[]): string {
  const names = sounds.map(soundName)
  const text =
    names.length <= 1
      ? (names[0] ?? "")
      : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
  return text.charAt(0).toUpperCase() + text.slice(1)
}

/** One line on what the atmosphere is doing, for the player's music panel. */
export function describeAtmosphere(status: LofiMusicStatus): string {
  const atmosphere = status.atmosphere
  if (!atmosphere?.available) return "Not in this version of the app"
  if (!atmosphere.enabled) return "Atmosphere is off"
  if (atmosphere.preparing) return "Getting the sounds ready…"
  if (atmosphere.source === "none") return "No sounds yet"
  const book = status.book
  if (!book) {
    return "Plays with readaloud books that have an atmosphere track"
  }
  if (book.text === "unavailable") {
    return "This book has no text for the sounds to follow"
  }
  if (book.text !== "ready") return "Reading the book…"
  if (!atmosphere.track) return "This book has no atmosphere track yet"
  if (status.playback.routeMuted) return "Off in the car"
  if (!status.playback.narrating) return "Plays with the narration"
  if (atmosphere.playing.length === 0) return "Quiet here"
  const sounds = soundList(atmosphere.playing)
  return atmosphere.musicYielding ? `${sounds}, with the music paused` : sounds
}

/** Where the atmosphere's sounds come from, for Settings. */
export function atmosphereSourceLabel(
  atmosphere: NonNullable<LofiMusicStatus["atmosphere"]>,
): string {
  switch (atmosphere.source) {
    case "imported":
      return `${atmosphere.sounds} of ${atmosphere.totalSounds} sounds, imported`
    case "mixed":
      return `${atmosphere.sounds} sounds: imported recordings, with stand-ins for the rest`
    case "standIns":
      return "Stand-in sounds. Import recordings (an Atmosphere folder in the music folder) for the real thing."
    case "none":
      return atmosphere.preparing
        ? "Getting the sounds ready…"
        : "No sounds yet"
  }
}

/** The music level, as the slider shows it. */
export function musicLevelLabel(levelDB: number): string {
  const under = Math.round(-levelDB)
  if (under <= 0) return "As loud as the voice"
  return `${under} dB under the voice`
}

/** Where the music comes from, for Settings. */
export function musicSourceLabel(library: LofiMusicStatus["library"]): string {
  const tracks = library.tracks === 1 ? "1 track" : `${library.tracks} tracks`
  switch (library.source) {
    case "imported":
      return library.importedFolderName
        ? `${tracks} from “${library.importedFolderName}”`
        : `${tracks}, imported`
    case "placeholders":
      return `${tracks} of stand-in music. Import your own for the real thing.`
    case "none":
      return library.preparing ? "Getting the music ready…" : "No music yet"
  }
}

/** "Calm 4 · Cozy 4 · …", with the moods that have no tracks at the end. */
export function moodCounts(library: LofiMusicStatus["library"]): string {
  const withTracks = library.moods.filter((mood) => mood.tracks > 0)
  const empty = library.moods.filter((mood) => mood.tracks === 0)
  const parts = withTracks.map(
    (mood) => `${moodName(mood.mood)} ${mood.tracks}`,
  )
  if (empty.length > 0) {
    parts.push(`no ${empty.map((mood) => moodName(mood.mood)).join(", ")} yet`)
  }
  return parts.join(" · ")
}

/**
 * The music's CREDITS.md as plain text for the credits screen: headings, bold
 * and links lose their Markdown marks, and a link keeps its address.
 */
export function plainCredits(markdown: string): string {
  return markdown
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((line) =>
      line
        .replace(/^#{1,6}\s+/, "")
        .replace(/^(\s*)[-*]\s+/, "$1• ")
        .replace(
          /\[([^\]]+)\]\(([^)\s]+)\)/g,
          (_, text: string, url: string) =>
            text === url ? url : `${text} (${url})`,
        )
        .replace(/(\*\*|__)(.+?)\1/g, "$2")
        .replace(/`([^`]+)`/g, "$1"),
    )
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
}
