// LOFI-FORK: the podcasts section's own audio files (see FORK.md).
//
// Audio files the listener adds from the Files app live in one local show, "Your files". It
// has no schema of its own: it is a row in `shows` with a reserved id and a feed address that
// is not a web address, so no feed code can fetch it. Each file is an episode installed like
// a finished download (see PodcastKit's AudioImport). Pure rules only; the database part is
// dbLocalFiles.ts.

export const LOCAL_SHOW_ID = "local-files"
export const LOCAL_FEED_URL = "local:files"
export const LOCAL_SHOW_TITLE = "Your files"
export const LOCAL_SHOW_NOTES =
  "Audio files you added from the Files app. They stay on this phone."
/** Stored as the show's image address; the screens draw a plain tile for it. */
export const LOCAL_ARTWORK = "local:artwork"
/** The player needs a web-looking address; the downloaded file is played instead. */
const LOCAL_AUDIO_HOST = "files.invalid"

/** The ids Swift gives an added file's episode (PodcastKit's AudioImport.idPrefix). */
export function isLocalEpisodeId(id: string): boolean {
  return id.startsWith("file-")
}

export function isLocalFeedUrl(feedUrl: string): boolean {
  return feedUrl === LOCAL_FEED_URL
}

/** The shows that have a feed: refreshing, OPML, Apple Podcasts and Discover use only these. */
export function feedShows<T extends { feedUrl: string }>(
  shows: readonly T[],
): T[] {
  return shows.filter((show) => !isLocalFeedUrl(show.feedUrl))
}

/** Whether an audio address is the stand-in of an added file (nothing to share or fetch). */
export function isLocalAudioUrl(url: string): boolean {
  return url.startsWith(`https://${LOCAL_AUDIO_HOST}/`)
}

export function localAudioUrl(
  episodeId: string,
  fileExtension: string,
): string {
  return `https://${LOCAL_AUDIO_HOST}/${episodeId}.${fileExtension}`
}

const TYPES: Record<string, string> = {
  mp3: "audio/mpeg",
  m4a: "audio/mp4",
  m4b: "audio/mp4",
  mp4: "audio/mp4",
  aac: "audio/aac",
  wav: "audio/wav",
  aif: "audio/aiff",
  aiff: "audio/aiff",
  caf: "audio/x-caf",
  flac: "audio/flac",
}

/** What Swift's importAudioFile reports for one installed file. */
export type ImportedAudio = {
  episodeId: string
  title: string
  durationSeconds: number | null
  bytes: number
  fileExtension: string
}

/** The values for the episode row of an added file. */
export function localEpisodeValues(file: ImportedAudio, now: number) {
  return {
    id: file.episodeId,
    guid: file.episodeId,
    title: file.title,
    publishedAt: now,
    durationSeconds: file.durationSeconds,
    audioUrl: localAudioUrl(file.episodeId, file.fileExtension),
    audioType: TYPES[file.fileExtension] ?? "audio/mpeg",
    audioBytes: file.bytes,
  }
}

/** A new name for a file: trimmed, or null when nothing is left. */
export function cleanName(text: string): string | null {
  const name = text.trim()
  return name === "" ? null : name
}

/** What to tell the listener after adding files. */
export function importSummary(
  added: number,
  already: number,
  failed: readonly { name: string; reason: string }[],
): string {
  const lines: string[] = []
  if (added > 0)
    lines.push(added === 1 ? "Added 1 file." : `Added ${added} files.`)
  if (already > 0) {
    lines.push(
      already === 1
        ? "1 file was already added."
        : `${already} files were already added.`,
    )
  }
  for (const { name, reason } of failed.slice(0, 5)) {
    lines.push(`${name}: ${reason}`)
  }
  if (failed.length > 5) lines.push(`and ${failed.length - 5} more failed`)
  return lines.join("\n")
}
