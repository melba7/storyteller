// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import { requireOptionalNativeModule } from "expo-modules-core"

import type { ImportedAudio } from "./localFiles"
import type { PlaybackSettings } from "./playbackSettings"

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
  /** Every `podcast:transcript` tag of the episode. */
  transcripts?: { url: string; type: string; language?: string; rel?: string }[]
  /** The `podcast:chapters` JSON file's address. */
  chaptersUrl?: string | null
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
  /** The show, so the player can apply the show's own settings. */
  showId?: string | null
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
  /** The feed's JSON chapters file, for the chapters of an episode that is not downloaded. */
  chaptersUrl?: string | null
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

/** Where an episode's ad finding is, as the Swift side reports it (once its transcript is ready). */
export type AdsInfo = {
  episodeId: string
  state: "waiting" | "finding" | "found" | "noAds" | "unavailable"
  /** 0 to 100 while finding. */
  percent?: number
  /** How many ads were found, with "found". */
  count?: number
  /** Plain words for an unavailable one ("Apple Intelligence is off"). */
  reason?: string
}

/** An episode's ad finding changed, or (state "none") went with its download. */
export type AdsChange = AdsInfo | { episodeId: string; state: "none" }

/** The player skipped an ad (the app shows "Skipped ad (1:05)" with Undo for a few seconds). */
export type AdSkipped = {
  episodeId: string
  /** Seconds: where the ad started and ended. */
  start: number
  end: number
  /** Seconds: how long the ad was. */
  length: number
}

/** The listener undid the skip of the ad that started here. */
export type AdUndone = { episodeId: string; start: number }

/** The two switches for skipping ads, both on until turned off. */
export type AdSkipSettings = { skipAds: boolean; skipOwnPlugs: boolean }

/** An episode in Up Next, with what the player needs to start it without JavaScript. */
export type UpNextItem = {
  id: string
  /** The show, for its settings; missing in a queue saved before per-show settings. */
  showId?: string | null
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
  /** The feed's JSON chapters file; missing in a queue saved before chapters. */
  chaptersUrl?: string | null
}

/** The queue changed. `items` is the whole queue, in play order. */
export type UpNextChange = { items: UpNextItem[] }

/** The player started the next queued episode by itself. */
export type PlaybackAdvanced = { episodeId: string }

/** One chapter of the loaded episode, as Swift sends it. */
export type PodcastChapter = {
  /** Seconds. */
  start: number
  /** Seconds, when the source says where it ends. */
  end?: number
  title: string
  /** A web address, or a file address for a picture read from an MP3. */
  imageUrl: string | null
  url: string | null
  /** The listener switched this chapter off: the player jumps over it. */
  skipped: boolean
}

/** The chapters of the loaded episode (none until they are read). */
export type ChaptersInfo = { episodeId: string; chapters: PodcastChapter[] }

/** The sleep timer: off, a countdown that ends at `endsAt` (milliseconds), or the episode's end. */
export type SleepTimerState =
  | { kind: "none" }
  | { kind: "countdown"; endsAt: number }
  | { kind: "endOfEpisode" }
  /** `chapterEnd` is the second of the episode where the chapter ends. */
  | { kind: "endOfChapter"; chapterEnd: number }

export type PodcastsEvents = {
  onChaptersChange: (info: ChaptersInfo) => void
  onSleepTimerChange: (state: SleepTimerState) => void
  onUpNextChange: (change: UpNextChange) => void
  onPlaybackAdvanced: (event: PlaybackAdvanced) => void
  onDownloadChange: (change: DownloadChange) => void
  onTranscriptChange: (change: TranscriptChange) => void
  onAdsChange: (change: AdsChange) => void
  onAdSkipped: (event: AdSkipped) => void
  onAdUndone: (event: AdUndone) => void
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

  /** Saves every show's playback settings (JSON, show id to settings) for the player. */
  writeShowSettings(json: string): Promise<void>

  /** "granted", "denied" or "undetermined" (not asked yet). */
  notificationPermission(): Promise<"granted" | "denied" | "undetermined">
  /** Asks the listener (iOS shows its question the first time). True when allowed. */
  requestNotificationPermission(): Promise<boolean>
  /** Shows a local notification now; one with the same id replaces it. Needs permission. */
  postNotification(id: string, title: string, body: string): Promise<void>

  /** The listener's playback settings, as Swift keeps them (see playbackSettings.ts). */
  getPlaybackSettings(): Promise<PlaybackSettings>
  /** Saves the settings; a value that is not a choice keeps its default. Returns what was kept. */
  setPlaybackSettings(settings: PlaybackSettings): Promise<PlaybackSettings>

  /** Counts down this many minutes (1 to 720), then fades out and pauses. */
  startSleepTimer(minutes: number): Promise<void>
  sleepUntilEndOfEpisode(): Promise<void>
  /** Stops where the chapter playing now ends. Rejects when the episode has no chapters. */
  sleepUntilEndOfChapter(): Promise<void>
  /** Adds 5 minutes to a running countdown. */
  extendSleepTimer(): Promise<void>
  cancelSleepTimer(): Promise<void>
  getSleepTimer(): Promise<SleepTimerState>

  /** The chapters of the loaded episode. */
  getChapters(): Promise<ChaptersInfo>
  /** Goes to the start of this chapter (after 3 seconds into it) or of the one before. */
  previousChapter(): Promise<void>
  /** Goes to the start of the next chapter. */
  nextChapter(): Promise<void>
  /** Switches a chapter's skipping on or off (`start` is the chapter's start in seconds). */
  setChapterSkipped(
    episodeId: string,
    start: number,
    skipped: boolean,
  ): Promise<void>

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
  /**
   * Copies an audio file from the Files app in and installs it like a finished download. The
   * answer has the episode's id (from the file's content), title, length, size and extension.
   */
  importAudioFile(uri: string, fileName: string | null): Promise<ImportedAudio>
  /** Stops a download that is not finished and forgets it. */
  cancelDownload(episodeId: string): Promise<void>
  /** Removes a download: the audio, its side files and its entry. */
  deleteDownload(episodeId: string): Promise<void>
  listDownloads(): Promise<DownloadInfo[]>
  /** Where each downloaded episode's transcript is. */
  listTranscripts(): Promise<TranscriptInfo[]>
  /** A finished transcript as JSON (`Transcript` in PodcastTranscripts), or null. */
  getTranscript(episodeId: string): Promise<string | null>
  /** Where each transcribed episode's ad finding is. */
  listAds(): Promise<AdsInfo[]>
  /** An episode's saved ads as JSON (`AdsFile` in PodcastAds), or null. */
  getAds(episodeId: string): Promise<string | null>
  getAdSkipSettings(): Promise<AdSkipSettings>
  setAdSkipSettings(skipAds: boolean, skipOwnPlugs: boolean): Promise<void>
  /**
   * Takes back the skip that was just made: back to the ad's start, playing, and the skip is
   * recorded as wrong. False when it is too late.
   */
  undoAdSkip(): Promise<boolean>
  /**
   * What silence trimming has saved so far, in seconds of audio, kept in Swift so a stats
   * screen can read it.
   */
  getTrimSavings(): Promise<number>
  /** The listening stats (`ListeningStats` in PodcastPlayback) as a plain object. */
  getStats(): Promise<Record<string, unknown>>
  /** Clears the listening stats. */
  resetStats(): Promise<void>
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
