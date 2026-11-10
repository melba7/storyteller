// LOFI-FORK: wording for the lofi music's state (see FORK.md).
import type {
  LofiMoodFeedback,
  LofiMoodOverride,
  LofiMusicStatus,
  LofiNowPlaying,
} from "./index"

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
  const reading = !status.playback.narrating && status.playback.reading
  if (!status.playback.narrating && !reading) {
    return status.followsReading
      ? "Plays with the narration, or as you turn the pages"
      : "Plays with the narration"
  }
  if (status.playback.musicMood) {
    return reading
      ? `Playing ${status.playback.musicMood} music as you read`
      : `Playing ${status.playback.musicMood} music`
  }
  return "Starting…"
}

/** The music is audible now, so its mood can be marked wrong. */
export function canMarkWrongMood(status: LofiMusicStatus): boolean {
  return (
    status.enabled &&
    !status.playback.routeMuted &&
    (status.playback.narrating || status.playback.reading === true) &&
    status.playback.musicMood !== undefined
  )
}

/** “Sky Lake” by Purrple Cat · CC BY 3.0, for the music panel. */
export function nowPlayingLine(track: LofiNowPlaying): string {
  let line = `“${track.title}”`
  if (track.artist) line += ` by ${track.artist}`
  if (track.license) line += ` · ${track.license}`
  return line
}

/** What the "Wrong mood" button just did. */
export function wrongMoodResult(result: LofiMoodOverride): string {
  return `Switched to ${result.chosen} music. Still wrong? Pick the mood.`
}

/** "You marked 1 of 9 mood changes wrong in this book", or null before any. */
export function moodFeedbackLine(feedback: LofiMoodFeedback): string | null {
  if (feedback.bookChanges === 0 && feedback.bookWrong === 0) return null
  const changes =
    feedback.bookChanges === 1
      ? "1 mood change"
      : `${feedback.bookChanges} mood changes`
  return `You marked ${feedback.bookWrong} of ${changes} wrong in this book`
}

/** "2 of 31 mood changes marked wrong (6%)", for Settings, or null before any. */
export function moodFeedbackTotals(feedback: LofiMoodFeedback): string | null {
  if (feedback.totalChanges === 0 && feedback.totalWrong === 0) return null
  const changes =
    feedback.totalChanges === 1
      ? "1 mood change"
      : `${feedback.totalChanges} mood changes`
  const share =
    feedback.totalChanges > 0
      ? ` (${Math.round((100 * feedback.totalWrong) / feedback.totalChanges)}%)`
      : ""
  return `${feedback.totalWrong} of ${changes} marked wrong${share}`
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
  if (!status.playback.narrating && !status.playback.reading) {
    return "Plays with the narration"
  }
  if (atmosphere.playing.length === 0) return "Quiet here"
  const sounds = soundList(atmosphere.playing)
  return atmosphere.musicYielding ? `${sounds}, with the music paused` : sounds
}

/** Where the atmosphere's sounds come from, for Settings. */
export function atmosphereSourceLabel(
  atmosphere: NonNullable<LofiMusicStatus["atmosphere"]>,
): string {
  const more = atmosphere.variants
    ? `, and ${atmosphere.variants} more specific ${atmosphere.variants === 1 ? "sound" : "sounds"}`
    : ""
  switch (atmosphere.source) {
    case "imported":
      return `${atmosphere.sounds} of ${atmosphere.totalSounds} sounds, imported${more}`
    case "mixed":
      return `${atmosphere.sounds} sounds: imported recordings, with stand-ins for the rest${more}`
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

/**
 * "Kept up to date with “LofiMusic”. Last checked 5 minutes ago: new: 1 book
 * score", for the settings screen. `now` is for tests.
 */
export function linkedFolderLabel(
  folder: NonNullable<LofiMusicStatus["library"]["linkedFolder"]>,
  now: number = Date.now(),
): string {
  const parts = [`Kept up to date with “${folder.name}”.`]
  if (folder.syncing) {
    parts.push("Checking it now…")
  } else if (folder.lastSync !== undefined) {
    parts.push(`Last checked ${timeAgo(folder.lastSync * 1000, now)}.`)
  }
  if (!folder.syncing && folder.lastResult) {
    parts.push(
      folder.lastResult.charAt(0).toUpperCase() +
        folder.lastResult.slice(1) +
        ".",
    )
  }
  return parts.join(" ")
}

/**
 * The open book's id when its text is ready and it lacks a mood track, or an
 * atmosphere track where the atmosphere can play; null otherwise. The app then
 * asks the server for the book's score.
 */
export function bookNeedingScore(
  status: LofiMusicStatus | null | undefined,
): string | null {
  const book = status?.book
  if (!book || book.text !== "ready") return null
  const atmosphere = status.atmosphere
  const atmosphereMissing = atmosphere?.available === true && !atmosphere.track
  return !book.moodTrack || atmosphereMissing ? book.id : null
}

/** "just now", "5 minutes ago", "3 hours ago", "2 days ago". */
export function timeAgo(then: number, now: number = Date.now()): string {
  const seconds = Math.max(0, Math.round((now - then) / 1000))
  if (seconds < 60) return "just now"
  const minutes = Math.round(seconds / 60)
  if (minutes < 60)
    return minutes === 1 ? "a minute ago" : `${minutes} minutes ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return hours === 1 ? "an hour ago" : `${hours} hours ago`
  const days = Math.round(hours / 24)
  return days === 1 ? "yesterday" : `${days} days ago`
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
