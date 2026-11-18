// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// What a row says about an episode's ad finding, how a change from Swift updates what the
// screens know, and the list of ads on the episode card. The finding itself is Swift
// (PodcastAds); this file does not need the native module.
import type { AdSkipped, AdUndone, AdsChange, AdsInfo } from "./index"

/** What the screens know about ad finding, by episode id. */
export type AdsMap = Readonly<Record<string, AdsInfo>>

/** The map after a change from Swift. A removed episode leaves the map. */
export function applyAdsChange(map: AdsMap, change: AdsChange): AdsMap {
  if (change.state === "none") {
    if (!(change.episodeId in map)) return map
    const { [change.episodeId]: _removed, ...rest } = map
    return rest
  }
  return { ...map, [change.episodeId]: change }
}

export function adsMapFromList(list: readonly AdsInfo[]): AdsMap {
  return Object.fromEntries(list.map((info) => [info.episodeId, info]))
}

/** What a row says about the ads; empty when there is nothing to say. */
/**
 * Whether the saved ads file is read for this state: "found", and "finding" too, because the
 * full pass runs after the partial ones and the ads found so far stay listed meanwhile.
 */
export function readsAdsFile(info: AdsInfo | undefined): boolean {
  return info?.state === "found" || info?.state === "finding"
}

/** An ads file together with the episode it was read for. */
export type KeptAds = { episodeId: string; file: AdsFile | null }

/**
 * The file to show once a read came back for `episodeId`: while finding, an empty read keeps
 * the last file, but only when it was read for this same episode.
 */
export function adsFileAfterRead(
  state: AdsInfo["state"] | undefined,
  last: KeptAds | null,
  episodeId: string,
  read: AdsFile | null,
): AdsFile | null {
  if (read !== null || state !== "finding") return read
  return last !== null && last.episodeId === episodeId ? last.file : null
}

export function adsStatus(info: AdsInfo | undefined): string {
  if (!info) return ""
  switch (info.state) {
    case "waiting":
      return "Waiting to find ads"
    case "finding":
      return "Finding ads"
    case "found": {
      const count = Math.max(0, Math.floor(info.count ?? 0))
      const found = count === 1 ? "1 ad found" : `${count} ads found`
      return info.unchecked === true
        ? `${found}. Couldn't check some parts`
        : found
    }
    case "noAds":
      return info.unchecked === true
        ? "Couldn't check some parts for ads"
        : "No ads found"
    case "unavailable":
      return info.reason ?? "Can't find ads"
  }
}

/** How the reason of one episode's own failed run starts (PodcastAdFinder+Retry.swift). */
const EPISODE_FAILURE_PREFIX = "Finding ads stopped"

/**
 * Why ads can't be found on this phone, when any episode says so ("Apple Intelligence is
 * off"), else null. The reason belongs to the phone, not the episode, so one is enough. One
 * episode's own failure ("Finding ads stopped: ...") is not the phone's reason.
 */
export function unavailableReason(map: AdsMap): string | null {
  for (const info of Object.values(map)) {
    if (info.state !== "unavailable") continue
    if (info.reason?.startsWith(EPISODE_FAILURE_PREFIX)) continue
    return info.reason ?? "Ads can't be found"
  }
  return null
}

/** The line so far (the download's, then the transcript's) followed by the ads'. */
export function withAds(line: string, info: AdsInfo | undefined): string {
  return [line, adsStatus(info)].filter((part) => part !== "").join(" · ")
}

// MARK: The saved ads

export type AdKind = "ad" | "ownPlug"
export type AdConfidence = "sure" | "unsure" | "guess"

/** One ad as saved in `<sha256>.ads.<detector>.json`, in seconds of audio. */
export type FoundAd = {
  start: number
  end: number
  kind: AdKind
  advertiser: string
  confidence: AdConfidence
  firstWords: string
}

export type AdsFile = {
  ads: FoundAd[]
  /** The ads whose skip the listener took back. */
  undone: { start: number; end: number }[]
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value)
}

function readAd(value: unknown): FoundAd | null {
  if (typeof value !== "object" || value === null) return null
  const ad = value as Record<string, unknown>
  if (
    !isNumber(ad["start"]) ||
    !isNumber(ad["end"]) ||
    ad["end"] <= ad["start"]
  )
    return null
  if (ad["kind"] !== "ad" && ad["kind"] !== "ownPlug") return null
  const confidence = ad["confidence"]
  if (
    confidence !== "sure" &&
    confidence !== "unsure" &&
    confidence !== "guess"
  )
    return null
  return {
    start: ad["start"],
    end: ad["end"],
    kind: ad["kind"],
    advertiser: typeof ad["advertiser"] === "string" ? ad["advertiser"] : "",
    confidence,
    firstWords: typeof ad["firstWords"] === "string" ? ad["firstWords"] : "",
  }
}

/** The ads file as Swift saved it, or null when it cannot be read. Bad entries are left out. */
export function parseAdsFile(json: string): AdsFile | null {
  let value: unknown
  try {
    value = JSON.parse(json)
  } catch {
    return null
  }
  if (typeof value !== "object" || value === null) return null
  const file = value as Record<string, unknown>
  if (!Array.isArray(file["ads"])) return null
  const ads = (file["ads"] as unknown[])
    .map(readAd)
    .filter((ad): ad is FoundAd => ad !== null)
    .sort((a, b) => a.start - b.start)
  const undone = Array.isArray(file["undone"])
    ? (file["undone"] as unknown[]).flatMap((entry) => {
        const item = entry as Record<string, unknown> | null
        return item && isNumber(item["start"]) && isNumber(item["end"])
          ? [{ start: item["start"], end: item["end"] }]
          : []
      })
    : []
  return { ads, undone }
}

/** "1:05" or, from an hour on, "1:02:03". */
export function formatClock(seconds: number): string {
  const total = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const rest = String(total % 60).padStart(2, "0")
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${rest}`
    : `${minutes}:${rest}`
}

/** One line of the "Ads found" list. */
export type AdRow = {
  key: string
  /** Where to play from, in seconds. */
  start: number
  end: number
  /** The ad's start in the episode, "12:03". */
  time: string
  /** How long it is, "1:05". */
  length: string
  kind: string
  advertiser: string
  firstWords: string
  /** The player skips this ad (sure or unsure, and not undone). */
  skipped: boolean
  /** The detector was not sure about it (it is skipped all the same). */
  unsure: boolean
  /** The listener took the skip back. */
  undone: boolean
  /** What a screen reader says. */
  label: string
}

/**
 * The rows of the "Ads found" list, in order. Guesses are not listed. An unsure ad is listed
 * and skipped like a sure one. (Whether the host plugs are skipped is the listener's switch.)
 */
export function adRows(file: AdsFile): AdRow[] {
  return file.ads
    .filter((ad) => ad.confidence !== "guess")
    .map((ad) => {
      const undone = file.undone.some(
        (item) => Math.abs(item.start - ad.start) < 0.5,
      )
      const time = formatClock(ad.start)
      const length = formatClock(ad.end - ad.start)
      const kind = ad.kind === "ad" ? "Ad" : "Host plug"
      return {
        key: String(ad.start),
        start: ad.start,
        end: ad.end,
        time,
        length,
        kind,
        advertiser: ad.advertiser,
        firstWords: ad.firstWords,
        skipped: !undone,
        unsure: ad.confidence === "unsure",
        undone,
        label: [
          `${kind} at ${time}, ${length} long`,
          ad.advertiser,
          ad.confidence === "unsure" ? "not sure" : "",
        ]
          .filter((part) => part !== "")
          .join(", "),
      }
    })
}

// MARK: The note after a skip

/** How long the "Skipped ad" note stays, with its Undo button. */
export const SKIP_NOTE_MS = 6000

/** The note on the screen: the skip that just happened. */
export type SkipNote = {
  episodeId: string
  /** Where the skipped ad started, in seconds. */
  start: number
  /** How long it was, in seconds. */
  length: number
  /** When the note appeared, in milliseconds. */
  shownAt: number
}

export function skipNote(event: AdSkipped, now: number): SkipNote {
  return {
    episodeId: event.episodeId,
    start: event.start,
    length: event.length,
    shownAt: now,
  }
}

/** "Skipped ad (1:05)". */
export function skipNoteText(note: SkipNote): string {
  return `Skipped ad (${formatClock(note.length)})`
}

/** Whether the note is still to be shown at `now`. */
export function skipNoteShown(note: SkipNote | null, now: number): boolean {
  return note !== null && now - note.shownAt < SKIP_NOTE_MS
}

/** The note after an undo: gone when it was that skip's. */
export function noteAfterUndo(
  note: SkipNote | null,
  event: AdUndone,
): SkipNote | null {
  if (note?.episodeId === event.episodeId && note.start === event.start)
    return null
  return note
}

// MARK: Marks on the seek bar

/** Where an ad sits on the seek bar, as shares (0 to 1) of its length. */
export type AdMark = {
  left: number
  width: number
  skipped: boolean
  /** Not sure it is an ad: drawn faint, though it is skipped too. */
  unsure: boolean
}

/** The marks for the listed ads. Nothing while the length is not known. */
export function adMarks(
  rows: readonly Pick<AdRow, "start" | "end" | "skipped" | "unsure">[],
  duration: number | null,
): AdMark[] {
  if (duration === null || !(duration > 0)) return []
  return rows.flatMap((row) => {
    if (!(row.end > row.start) || row.start >= duration) return []
    const left = Math.max(0, row.start / duration)
    return [
      {
        left,
        width: Math.min(1 - left, (row.end - row.start) / duration),
        skipped: row.skipped,
        unsure: row.unsure,
      },
    ]
  })
}
