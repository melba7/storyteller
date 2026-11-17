// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import { requireOptionalNativeModule } from "expo-modules-core"

/** A podcast feed as the Swift side reads it. A value the feed lacks is missing or null. */
export type PodcastFeedData = {
  title: string
  author?: string | null
  /** Plain text. */
  description: string
  imageUrl?: string | null
  link?: string | null
  language?: string | null
  /** `itunes:category` names: top-level ones, then "Top › Sub" ones. */
  categories?: string[]
  /** In feed order. */
  episodes: PodcastFeedEpisode[]
}

export type PodcastFeedEpisode = {
  guid: string
  title: string
  /** Milliseconds since 1970. */
  publishedAt?: number | null
  durationSeconds?: number | null
  /** Plain text. */
  notes: string
  audioUrl: string
  audioType: string
  audioBytes?: number | null
  imageUrl?: string | null
  season?: number | null
  number?: number | null
}

/** What the player is doing, sent about twice a second while playing and on every change. */
export type PlaybackState = {
  /** Missing until an episode has been loaded. */
  episodeId?: string | null
  /** Seconds. */
  position: number
  /** Seconds, once known. */
  duration?: number | null
  isPlaying: boolean
  /** The listener wants to play but the stream is still loading. */
  isBuffering: boolean
  /** 0.5 to 3.0 in tenths. */
  rate: number
}

export type PlaybackLoadOptions = {
  episodeId: string
  url: string
  title: string
  showTitle: string
  artworkUrl?: string | null
  /** Where the listener left off. The player starts over for a played or nearly-over episode. */
  savedPosition: number
  duration?: number | null
  played: boolean
  autoplay: boolean
  /** The feed's audio type, kept for Up Next. */
  audioType: string
}

/** The episode played to its end. */
export type PlaybackEnded = {
  episodeId: string
  position: number
  duration: number
  played: true
}

export type PlaybackError = {
  episodeId: string
  /** Plain words for the listener. */
  message: string
}

/** Where an episode's download is, as the Swift side reports it. */
export type DownloadInfo = {
  episodeId: string
  state: "queued" | "downloading" | "downloaded" | "failed"
  /** Bytes so far while downloading; the file's size once downloaded. */
  bytes?: number
  /** Bytes expected, when the server said. */
  expected?: number
  /** The file name (`<sha256>.<ext>`) once downloaded. */
  file?: string
  sha256?: string
  /** Milliseconds since 1970 when the download finished. */
  date?: number
  /** Plain words for a failed download. */
  reason?: string
  /** Milliseconds since 1970. */
  updatedAt: number
}

/** A download changed, or (state "none") was removed. */
export type DownloadChange = DownloadInfo | { episodeId: string; state: "none" }

/** Where an episode's transcript is, as the Swift side reports it. */
export type TranscriptInfo = {
  episodeId: string
  state: "waiting" | "transcribing" | "done" | "unsupported" | "failed"
  /** 0 to 100 while transcribing. */
  percent?: number
  /** Plain words for an unsupported or failed one ("Needs iOS 26", "Language not supported"). */
  reason?: string
}

/** A transcript changed, or (state "none") went with its download. */
export type TranscriptChange =
  | TranscriptInfo
  | { episodeId: string; state: "none" }

/** An episode in Up Next, with what the player needs to start it without JavaScript. */
export type UpNextItem = {
  id: string
  url: string
  /** The feed's audio type. */
  type: string
  title: string
  showTitle: string
  artworkUrl?: string | null
  /** Seconds, when known. */
  duration?: number | null
  /** Where the listener left off, in seconds. */
  position: number
}

/** The queue changed. `items` is the whole queue, in play order. */
export type UpNextChange = { items: UpNextItem[] }

/** The player started the next queued episode by itself. */
export type PlaybackAdvanced = { episodeId: string }

export type PodcastsEvents = {
  onUpNextChange: (change: UpNextChange) => void
  onPlaybackAdvanced: (event: PlaybackAdvanced) => void
  onDownloadChange: (change: DownloadChange) => void
  onTranscriptChange: (change: TranscriptChange) => void
  onPlaybackState: (state: PlaybackState) => void
  onPlaybackEnded: (event: PlaybackEnded) => void
  onPlaybackError: (event: PlaybackError) => void
}

type PodcastsNativeModule = {
  /** Downloads and reads the feed. Rejects with a message the listener can read. */
  fetchFeed(url: string): Promise<PodcastFeedData>

  /** Loads an episode and, with `autoplay`, starts it. */
  load(options: PlaybackLoadOptions): Promise<void>
  play(): Promise<void>
  pause(): Promise<void>
  togglePlayPause(): Promise<void>
  seekTo(seconds: number): Promise<void>
  /** Jumps by this many seconds (negative for back), staying inside the episode. */
  skipBy(seconds: number): Promise<void>
  /** Ahead 45 seconds. */
  skipForward(): Promise<void>
  /** Back 10 seconds. */
  skipBack(): Promise<void>
  /** Sets the speed, rounded to 0.1 within 0.5 to 3.0, and returns the speed in use. */
  setRate(rate: number): Promise<number>
  getPlaybackState(): Promise<PlaybackState>
  /** The main colour of the picture as "#rrggbb", or null when it can't be read. */
  artworkColor(url: string): Promise<string | null>

  listUpNext(): Promise<UpNextItem[]>
  /** Puts an episode at the top ("next") or the bottom ("last"). One already queued moves. */
  addToUpNext(item: UpNextItem, place: "next" | "last"): Promise<void>
  moveInUpNext(from: number, to: number): Promise<void>
  removeFromUpNext(id: string): Promise<void>
  clearUpNext(): Promise<void>

  /**
   * Starts downloading an episode. It carries on with the app closed. `automatic` is for new
   * episodes the app fetches by itself: they always wait for Wi-Fi. `language` is the
   * feed's, for the transcript (null: the phone's).
   */
  download(
    episodeId: string,
    url: string,
    type: string,
    automatic: boolean,
    language: string | null,
  ): Promise<void>
  /** Stops a download that is not finished and forgets it. */
  cancelDownload(episodeId: string): Promise<void>
  /** Removes a download: the audio, its side files and its entry. */
  deleteDownload(episodeId: string): Promise<void>
  listDownloads(): Promise<DownloadInfo[]>
  /** Where each downloaded episode's transcript is. */
  listTranscripts(): Promise<TranscriptInfo[]>
  /** A finished transcript as JSON (`Transcript` in PodcastTranscripts), or null. */
  getTranscript(episodeId: string): Promise<string | null>
  /** Bytes taken by finished downloads. */
  storageUsed(): Promise<number>
  setWifiOnly(on: boolean): Promise<void>
  getWifiOnly(): Promise<boolean>
  addListener<E extends keyof PodcastsEvents>(
    event: E,
    listener: PodcastsEvents[E],
  ): { remove(): void }
}

/** The native module. Null on Android and the web, where the section is not available. */
export const Podcasts =
  requireOptionalNativeModule<PodcastsNativeModule>("Podcasts")
