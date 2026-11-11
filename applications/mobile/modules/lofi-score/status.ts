// LOFI-FORK: wording for the atmosphere's state (see FORK.md).
import type {
  LofiAtmosphereStatus,
  LofiLinkedFolder,
  LofiStatus,
} from "./index"

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
    roomTone: "a quiet room",
    hushedRoom: "a hushed room",
    murmur: "murmuring voices",
    emptyHall: "an empty hall",
    electricHum: "an electric hum",
    kitchen: "a kitchen",
    workshop: "a workshop",
    farmyard: "a farmyard",
    motorVehicle: "an engine",
    aircraft: "an aircraft",
    spaceship: "a spaceship",
    deepDrone: "a deep drone",
    running: "running feet",
    heartbeat: "a heartbeat",
    fighting: "a fight",
    writing: "a pen on paper",
    meal: "a meal",
    work: "someone at work",
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

/** One line on what the atmosphere is doing, for the player's panel. */
export function describeAtmosphere(status: LofiStatus): string {
  const atmosphere = status.atmosphere
  if (!atmosphere.available) return "Not in this version of the app"
  if (!atmosphere.enabled) return "Atmosphere sounds are off"
  if (atmosphere.preparing) return "Getting the sounds ready…"
  if (atmosphere.source === "none") return "No sounds yet"
  const book = status.book
  if (!book) {
    return "Plays with readaloud books that have an atmosphere track"
  }
  if (book.text === "unavailable") {
    return "This book has no text for the sounds to follow"
  }
  if (book.text === "off") return "Plays with the narration"
  if (book.text !== "ready") return "Reading the book…"
  if (!atmosphere.track) return "This book has no atmosphere track yet"
  if (atmosphere.routeMuted) return "Off in the car"
  const reading = !status.playback.narrating && status.playback.reading
  if (!status.playback.narrating && !reading) {
    return status.followsReading
      ? "Plays with the narration, or as you turn the pages"
      : "Plays with the narration"
  }
  if (atmosphere.playing.length === 0) return "Quiet here"
  return soundList(atmosphere.playing)
}

/** Where the atmosphere's sounds come from, for Settings. */
export function atmosphereSourceLabel(
  atmosphere: LofiAtmosphereStatus,
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
      return "Stand-in sounds. Import a sounds folder (with an Atmosphere folder in it) for the real thing."
    case "none":
      return atmosphere.preparing
        ? "Getting the sounds ready…"
        : "No sounds yet"
  }
}

/** How much is going on in the atmosphere, as the slider shows it. */
export function intensityLabel(intensity: number): string {
  if (intensity <= 0.05) return "Just the main sound"
  if (intensity < 0.35) return "Sparse"
  if (intensity < 0.65) return "Some of the scene"
  if (intensity < 0.95) return "Most of the scene"
  return "The whole scene"
}

/** The sounds' level, as the slider shows it. */
export function levelLabel(levelDB: number): string {
  const under = Math.round(-levelDB)
  if (under <= 0) return "As loud as the voice"
  return `${under} dB under the voice`
}

/**
 * "Kept up to date with “LofiMusic”. Last checked 5 minutes ago: new: 1 book
 * score", for the settings screen. `now` is for tests.
 */
export function linkedFolderLabel(
  folder: LofiLinkedFolder,
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
 * The open book's id when its text is ready, the atmosphere can play and the
 * book lacks an atmosphere track; null otherwise. The app then asks the
 * server for the book's score.
 */
export function bookNeedingScore(
  status: LofiStatus | null | undefined,
): string | null {
  const book = status?.book
  if (!book || book.text !== "ready") return null
  const atmosphere = status.atmosphere
  return atmosphere.available && !atmosphere.track ? book.id : null
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

/**
 * The sounds' CREDITS.md as plain text for the credits screen: headings, bold
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
