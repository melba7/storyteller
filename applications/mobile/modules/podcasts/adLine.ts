// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// The one quiet line in the player that says how ad finding is going for the episode that
// plays. Plain rules over what Swift reports; the texts of the ads and the transcript come
// from ads.ts and transcripts.ts.
import { AD_CHECK_PAUSED, MAC_MARKS, SEARCH_STOPPED, adsStatus } from "./ads"
import type { AdsInfo, DownloadInfo, TranscriptInfo } from "./index"
import { isLocalEpisodeId } from "./localFiles"
import { isPreviewId } from "./preview"
import { transcriptStatus } from "./transcripts"

const READY = "Getting ready to find ads"
const STREAMING = "Streaming without ad skipping"
const CHECKING = "Checking the start for ads"

function cannot(reason: string): string {
  return reason === "" ? "Ads can't be found" : `Ads can't be found: ${reason}`
}

function percentOf(value: number | undefined): number | null {
  return value === undefined
    ? null
    : Math.max(0, Math.min(100, Math.floor(value)))
}

/**
 * What the player says about ad finding: empty while Skip ads is off or for an added file or
 * a preview. A plain stream (no download, a failed one, or the player playing the plain
 * address while the download is made) is "Streaming without ad skipping", because ads are
 * skipped only in a file on the phone.
 */
export function playerAdLine(input: {
  episodeId: string
  skipAds: boolean
  download: DownloadInfo | undefined
  transcript?: TranscriptInfo | undefined
  ads?: AdsInfo | undefined
  /** The player plays the plain address, whatever the download says (Swift reports it). */
  streamsPlain?: boolean
  /** Play is waiting a moment for the first look at the start of a stream (Swift reports it). */
  checkingStart?: boolean
  /** The skips of the stream that plays come from the Mac's marks (Swift reports it). */
  macMarks?: boolean
}): string {
  const { episodeId, skipAds, download, transcript, ads } = input
  if (!skipAds) return ""
  if (isLocalEpisodeId(episodeId) || isPreviewId(episodeId)) return ""
  // Play waits for the first look at a stream's start while its download is still arriving,
  // which would read "Getting ready", so this comes first.
  if (input.checkingStart === true) return CHECKING
  // A stream is not in the table of downloads, so the player says when its skips are the Mac's.
  if (input.macMarks === true && download?.state !== "downloaded")
    return MAC_MARKS
  const noFile = download === undefined || download.state === "failed"
  // The Mac's marks skip in the head of a stream too, when the phone knows them for the episode.
  if (noFile) return ads?.macMarks === true ? MAC_MARKS : STREAMING
  // The download is being prepared, but the item that plays is not that file: nothing is
  // skipped until the episode is loaded again, so the ads found are not claimed.
  if (input.streamsPlain === true)
    return `${STREAMING}. Next play will skip ads.`
  if (download.state !== "downloaded") return READY
  if (ads?.state === "unavailable") {
    const reason = ads.reason ?? ""
    // The reasons that belong to the phone ("Apple Intelligence is off") keep their words.
    return reason.startsWith(SEARCH_STOPPED) ? AD_CHECK_PAUSED : cannot(reason)
  }
  if (ads?.state === "found" || ads?.state === "noAds") return adsStatus(ads)
  if (transcript?.state === "unsupported" || transcript?.state === "failed") {
    return cannot(transcriptStatus(transcript))
  }
  if (transcript?.state === "transcribing") {
    const percent = percentOf(transcript.percent)
    return percent === null
      ? "Finding ads"
      : `Finding ads, ${percent}% transcribed`
  }
  if (ads?.state === "finding") {
    const percent = percentOf(ads.percent)
    return percent === null ? "Finding ads" : `Finding ads, ${percent}%`
  }
  return READY
}

/**
 * The ads part of an episode's status line: nothing before the audio is on the phone. Before
 * the transcript is done only the reason and the results show, not "Waiting to find ads".
 */
export function adsToShow(
  downloaded: boolean,
  transcript: TranscriptInfo | undefined,
  ads: AdsInfo | undefined,
): AdsInfo | undefined {
  if (!downloaded || ads === undefined) return undefined
  if (transcript?.state === "done") return ads
  return ads.state === "waiting" || ads.state === "finding" ? undefined : ads
}
