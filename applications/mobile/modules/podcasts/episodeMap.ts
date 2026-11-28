// LOFI-FORK: the podcasts section's episode maps from the Mac (see FORK.md).
//
// The Mac marks an episode on its own copy and writes a small map of that copy into the linked
// folder (`Podcasts/maps/<id>.json`, about 185 KB for an hour). With the map the phone carries
// the Mac's marks over to whatever download of the episode it plays, by the audio itself. The
// native side knows which map the playing episode needs; this fetches it. Nothing here touches the
// native modules (episodeMapRun.ts does), so the rules are tested without them.

/** What one try to fetch an episode's map came to. */
export type MapFetch = "none" | "installed" | "refused" | "waiting"

/** What reading a file of the linked folder found (the part of `LinkedFileRead` used here). */
export type MapRead = { status: string; text?: string }

/** The native side and the linked folder, as this needs them. */
export interface MapSource {
  /** The map to fetch for the episode (`maps/<name>.json`), or null when none is needed. */
  wanted(episodeId: string): Promise<string | null>
  /** Reads a small text file below the linked folder. */
  read(path: string): Promise<MapRead>
  /** Hands the map's text to the native side. True when it was the episode's map. */
  install(episodeId: string, text: string): Promise<boolean>
}

/** A map iCloud has not brought yet is tried this many times in all. */
export const MAP_TRIES = 6
/** How long to wait between two tries (milliseconds). */
export const MAP_WAIT_MS = 20 * 1000
/** While an episode plays, the Mac's files are looked at again this often (milliseconds). */
export const MAP_LOOK_MS = 5 * 60 * 1000

/** Whether `path` is `maps/<name>.json` with one plain name, so a read never leaves that folder. */
export function isMapPath(path: string): boolean {
  return (
    /^maps\/[A-Za-z0-9_-][A-Za-z0-9._-]*\.json$/.test(path) &&
    !path.includes("..")
  )
}

/**
 * One try: asks the native side which map the episode needs, reads it from the linked folder and
 * installs it. "waiting" when iCloud has not brought the file yet (the read asks iCloud for it).
 */
export async function fetchEpisodeMap(
  episodeId: string,
  source: MapSource,
): Promise<MapFetch> {
  const path = await source.wanted(episodeId)
  if (path === null || !isMapPath(path)) return "none"
  const read = await source.read(`Podcasts/${path}`)
  if (read.status === "notDownloaded" || read.status === "missing")
    return "waiting"
  if (read.status !== "found" || typeof read.text !== "string") return "none"
  return (await source.install(episodeId, read.text)) ? "installed" : "refused"
}

/**
 * Whether to try again after `tries` tries: only while the file is on its way and the episode is
 * still the one whose map is wanted.
 */
export function mapTryAgain(
  result: MapFetch,
  tries: number,
  stillWanted: boolean,
): boolean {
  return result === "waiting" && tries < MAP_TRIES && stillWanted
}
