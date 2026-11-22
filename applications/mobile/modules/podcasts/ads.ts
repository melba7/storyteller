// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// What a row says about an episode's ad finding, how a change from Swift updates what the
// screens know, and the list of ads on the episode card. The finding itself is Swift
// (PodcastAds); this file does not need the native module.
import type {
  AdSkipSettings,
  AdSkipped,
  AdUndone,
  AdsChange,
  AdsInfo,
} from "./index"

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

/**
 * How the words for a failure of one episode's own search start (`PodcastAdFinder.reason(for:)`
 * in Swift). The rest of them, with any technical tail, is for the log, not for a line that
 * has room for one row.
 */
export const SEARCH_STOPPED = "Finding ads stopped:"

/** What a screen says for such a failure: it is asked again by itself, so nothing is wrong. */
export const AD_CHECK_PAUSED = "Ad check paused. Trying again soon"

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
    case "unavailable": {
      const reason = info.reason ?? "Can't find ads"
      // The reasons that belong to the phone ("Apple Intelligence is off") keep their words.
      return reason.startsWith(SEARCH_STOPPED) ? AD_CHECK_PAUSED : reason
    }
  }
}

/**
 * The reasons that belong to the phone, as `AdUnavailable.reason` in PodcastAds writes them
 * (and the Swift that passes them on): Apple Intelligence off, not supported, the model not
 * ready or downloading, iOS too old, and the system's catch-all. Any other reason is one
 * episode's own failure ("The transcript could not be read", "Finding ads stopped: ...").
 */
const PHONE_REASONS: readonly string[] = [
  "Apple Intelligence is off",
  "The model is downloading",
  "This iPhone can't run Apple Intelligence",
  "Needs iOS 26",
  "Apple Intelligence is not available",
]

/**
 * Why ads can't be found on this phone, when any episode says so ("Apple Intelligence is
 * off"), else null. The reason belongs to the phone, not the episode, so one is enough. Only
 * the phone-wide reasons count; the rest is one episode's failure.
 */
export function unavailableReason(map: AdsMap): string | null {
  for (const info of Object.values(map)) {
    if (info.state !== "unavailable") continue
    if (info.reason && PHONE_REASONS.includes(info.reason)) return info.reason
  }
  return null
}

/** The line so far (the download's, then the transcript's) followed by the ads'. */
export function withAds(line: string, info: AdsInfo | undefined): string {
  return [line, adsStatus(info)].filter((part) => part !== "").join(" · ")
}

// MARK: The saved ads

/** The four sorts: sponsor ads, the hosts' own plugs, promos for other things, intros and credits. */
export type AdKind = "ad" | "ownPlug" | "promo" | "credits"
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
  /** The ads as they are skipped: already cut short by the listener's trims. */
  ads: FoundAd[]
  /** The ads whose skip the listener took back. */
  undone: { start: number; end: number }[]
}

/** The sort a saved or reported name stands for. A name that is not known is taken for an ad. */
export function adKindOf(value: unknown): AdKind {
  return value === "ownPlug" || value === "promo" || value === "credits"
    ? value
    : "ad"
}

/** The switches until the listener changes them: credits are skipped only when asked for. */
export const DEFAULT_AD_SKIP_SETTINGS: AdSkipSettings = {
  skipAds: true,
  skipOwnPlugs: true,
  skipPromos: true,
  skipCredits: false,
}

/** The switches from what the phone sent: what it did not say (an older build) is the default. */
export function readAdSkipSettings(raw: unknown): AdSkipSettings {
  const given = (raw && typeof raw === "object" ? raw : {}) as Record<
    string,
    unknown
  >
  const flag = (key: keyof AdSkipSettings): boolean => {
    const value = given[key]
    return typeof value === "boolean" ? value : DEFAULT_AD_SKIP_SETTINGS[key]
  }
  return {
    skipAds: flag("skipAds"),
    skipOwnPlugs: flag("skipOwnPlugs"),
    skipPromos: flag("skipPromos"),
    skipCredits: flag("skipCredits"),
  }
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
    kind: adKindOf(ad["kind"]),
    advertiser: typeof ad["advertiser"] === "string" ? ad["advertiser"] : "",
    confidence,
    firstWords: typeof ad["firstWords"] === "string" ? ad["firstWords"] : "",
  }
}

type Trim = { adStart: number; end: number }

/** The trims of an ads file: where the listener found a skip too far. Bad entries are left out. */
function readTrims(value: unknown): Trim[] {
  if (!Array.isArray(value)) return []
  return (value as unknown[]).flatMap((entry) => {
    const item = entry as Record<string, unknown> | null
    return item && isNumber(item["adStart"]) && isNumber(item["end"])
      ? [{ adStart: item["adStart"], end: item["end"] }]
      : []
  })
}

/**
 * The ad cut short by the trims that are for it (as `AdTrim` in PodcastAds does): a trim is for
 * the ad that starts where it did, or runs over that place. An ad is never made longer; null
 * when a trim leaves it with no length.
 */
function trimmedAd(ad: FoundAd, trims: readonly Trim[]): FoundAd | null {
  let end = ad.end
  for (const trim of trims) {
    if (ad.start - 0.5 <= trim.adStart && trim.adStart < ad.end)
      end = Math.min(end, trim.end)
  }
  return end > ad.start ? { ...ad, end } : null
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
  const trims = readTrims(file["trims"])
  const ads = (file["ads"] as unknown[])
    .map(readAd)
    .filter((ad): ad is FoundAd => ad !== null)
    .flatMap((ad) => trimmedAd(ad, trims) ?? [])
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

/** What the "Ads found" list calls each sort. */
const KIND_LABELS: Record<AdKind, string> = {
  ad: "Ad",
  ownPlug: "Host plug",
  promo: "Promo",
  credits: "Credits",
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
      const kind = KIND_LABELS[ad.kind]
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
  /** What was skipped. */
  kind: AdKind
  /** When the note appeared, in milliseconds. */
  shownAt: number
}

export function skipNote(event: AdSkipped, now: number): SkipNote {
  return {
    episodeId: event.episodeId,
    start: event.start,
    length: event.length,
    kind: adKindOf(event.kind),
    shownAt: now,
  }
}

/** How far the note's "Back" button goes back. */
export const SKIP_NOTE_BACK_SECONDS = 10

/** What the note's "Back" button says, and what a screen reader says for it. */
export function skipNoteBackLabels(seconds: number = SKIP_NOTE_BACK_SECONDS): {
  text: string
  accessibility: string
} {
  return {
    text: `Back ${seconds} s`,
    accessibility: `Back ${seconds} seconds, the skip went too far`,
  }
}

const SKIPPED_WORDS: Record<AdKind, string> = {
  ad: "Skipped ad",
  promo: "Skipped promo",
  ownPlug: "Skipped the hosts' plug",
  credits: "Skipped credits",
}

/** "Skipped ad (1:05)", "Skipped promo (1:05)", "Skipped the hosts' plug (1:05)"... */
export function skipNoteText(note: SkipNote): string {
  return `${SKIPPED_WORDS[note.kind]} (${formatClock(note.length)})`
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
