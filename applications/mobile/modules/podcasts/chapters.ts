// LOFI-FORK: the podcasts section's chapters (see FORK.md).
//
// The pure parts the screens need: reading what Swift sends and finding the chapter that is
// playing. Swift owns the chapters of the loaded episode (it reads them from the file or the
// feed and does the skipping), so they work with the screen locked.
import type { PodcastChapter } from "./index"

function text(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null
}

function seconds(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : null
}

/** The chapters Swift sent, in order; anything that is not a chapter is left out. */
export function readChapters(value: unknown): PodcastChapter[] {
  if (!Array.isArray(value)) return []
  const chapters: PodcastChapter[] = []
  for (const entry of value as unknown[]) {
    if (typeof entry !== "object" || entry === null) continue
    const record = entry as Record<string, unknown>
    const start = seconds(record["start"])
    if (start === null) continue
    const end = seconds(record["end"])
    chapters.push({
      start,
      ...(end === null ? {} : { end }),
      title: text(record["title"]) ?? "Chapter",
      imageUrl: text(record["imageUrl"]),
      url: text(record["url"]),
      skipped: record["skipped"] === true,
    })
  }
  return chapters.sort((a, b) => a.start - b.start)
}

/**
 * The chapter playing at this place: the last one that has started. None before the first
 * one, and none after a chapter's own end when a gap follows it. (The same rule as Swift's
 * ChapterRules.current.)
 */
export function currentChapterIndex(
  chapters: readonly PodcastChapter[],
  position: number,
): number | null {
  if (!Number.isFinite(position)) return null
  let index = -1
  chapters.forEach((chapter, at) => {
    if (chapter.start <= position) index = at
  })
  const chapter = chapters[index]
  if (!chapter) return null
  if (chapter.end !== undefined && position >= chapter.end) {
    const next = chapters[index + 1]
    if (!next || next.start > chapter.end) return null
  }
  return index
}

/** Where a chapter ends: its own end, else where the next starts, else the episode's end. */
export function chapterEndOf(
  chapters: readonly PodcastChapter[],
  index: number,
  duration: number | null,
): number | null {
  const chapter = chapters[index]
  if (!chapter) return null
  if (chapter.end !== undefined) return chapter.end
  const next = chapters[index + 1]
  if (next) return next.start
  return duration !== null && duration > chapter.start ? duration : null
}

/** The picture of the chapter playing at this place, if it has one. */
export function chapterArtwork(
  chapters: readonly PodcastChapter[],
  position: number,
): string | null {
  const index = currentChapterIndex(chapters, position)
  return index === null ? null : (chapters[index]?.imageUrl ?? null)
}
