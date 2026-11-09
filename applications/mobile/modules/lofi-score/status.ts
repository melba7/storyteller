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
