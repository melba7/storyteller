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
  /** The channel's `podcast:person` tags (at most 20). */
  people?: PodcastPerson[]
  /** The channel's `podcast:funding` tags (at most 5). */
  funding?: PodcastFunding[]
  /** The channel's `itunes:new-feed-url`, left out when the feed has none. */
  newFeedUrl?: string
  /** In feed order. */
  episodes: PodcastFeedEpisode[]
}

/** A `podcast:person` tag. `img` and `href` are http(s) addresses or missing. */
export type PodcastPerson = {
  name: string
  role: string
  group: string
  img?: string | null
  href?: string | null
}

/** A `podcast:funding` tag. `label` is empty when the feed has no text. */
export type PodcastFunding = { url: string; label: string }

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
  /** The episode's own `podcast:person` tags. */
  people?: PodcastPerson[]
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
  /** The player plays the episode's plain address, so no ad is skipped. */
  streamsPlain?: boolean
  /**
   * Play is waiting a moment (3 seconds at most) for the first look at the start of a stream,
   * so an ad at 0:00 can be left before it is heard.
   */
  checkingStart?: boolean
  /** The skips of the stream that plays come from the Mac's marks (see `AdsInfo.macMarks`). */
  macMarks?: boolean
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
  /**
   * Play from the episode's own download as its bytes arrive (Skip ads is on and the episode
   * is not downloaded), so what is heard is the file that is saved and checked for ads. The
   * player may still stream, for example with Wi-Fi only on and no Wi-Fi.
   */
  playThroughDownload?: boolean
  /**
   * The start is the listener's own choice ("Play from" an ad, a bookmark or a transcript
   * line), so an ad that holds it is not skipped. Left out for every other load.
   */
  startChosen?: boolean
  /** The feed's language, for the transcript of the download that plays. */
  language?: string | null
  /** The episode's notes and the show's web page: sponsors named there help the ad rules. */
  notes?: string | null
  showLink?: string | null
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
  /** Asked for by the app by itself (a new episode), not by the listener. */
  automatic?: boolean
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

/** One place a search found its words: the line's start in seconds and the lines around it. */
export type SpokenHit = {
  episodeId: string
  seconds: number
  text: string
  before: string
  after: string
}

/** A transcript changed, or (state "none") went with its download. */
export type TranscriptChange =
  | TranscriptInfo
  | { episodeId: string; state: "none" }

/** What installing a prepared copy answered: "installed", or why not in one word. */
export type PreparedInstallAnswer =
  | "installed"
  | "noCopy"
  | "playing"
  | "downloading"
  | "size"
  | "hash"
  | "unreadable"
  | "adsNotSaved"
  | "failed"

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
  /** The model refused some parts of the transcript, so they were not checked for ads. */
  unchecked?: boolean
  /** The file is a copy the Mac prepared, and its ads are the Mac's marks on that very file. */
  prepared?: boolean
  /** The Mac's marks of the night before (`ahead-ads.json`) are for this episode, so they skip on its copy. */
  macMarks?: boolean
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
  /** The sort: "ad", "ownPlug", "promo" or "credits". Missing from an older build: an ad. */
  kind?: string
}

/** The listener undid the skip of the ad that started here. */
export type AdUndone = { episodeId: string; start: number }

/**
 * The playhead entered a stretch the phone is not sure is an ad, once for each question in a
 * playback. The app shows "Ad? Skip" with two answers (`answerAdQuestion`) until the stretch
 * ends. `start` and `end` are seconds into the episode; `kind` is the sort it would be.
 */
export type AdAsk = {
  episodeId: string
  start: number
  end: number
  kind: string
}

/**
 * The four switches for skipping: sponsor ads, the hosts' own plugs and promos are on until
 * turned off, intros and credits are off until turned on.
 */
export type AdSkipSettings = {
  skipAds: boolean
  skipOwnPlugs: boolean
  skipPromos: boolean
  skipCredits: boolean
}

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
  /** The show's language, for the transcript; missing in a queue saved before this. */
  language?: string | null
  /** The episode's notes (the first 4,000 characters) and the show's web page, for the ad rules. */
  notes?: string | null
  showLink?: string | null
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
  onAdAsk: (event: AdAsk) => void
  /** The headphones made a bookmark: `readPendingBookmarks` has it. */
  onBookmarksPending: () => void
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
  /**
   * The bookmarks the headphones made (`Podcasts/pending-bookmarks.json`) as a JSON list;
   * "[]" when there are none. They stay in the file until `removePendingBookmarks`.
   */
  readPendingBookmarks(): Promise<string>
  /** Takes the bookmarks with these ids out of the file, once they are saved. */
  removePendingBookmarks(ids: string[]): Promise<void>

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
    showId: string | null,
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
  /**
   * Looks at Up Next now and fetches the next episodes ahead where the rules allow it (never off
   * Wi-Fi). Called when the app comes to the front and in the background refresh. `held` are the
   * episodes the Mac is preparing a copy of: they are not fetched ahead.
   */
  lookAhead(held: string[]): Promise<void>
  /** Where each downloaded episode's transcript is. */
  listTranscripts(): Promise<TranscriptInfo[]>
  /** A finished transcript as JSON (`Transcript` in PodcastTranscripts), or null. */
  getTranscript(episodeId: string): Promise<string | null>
  /** The lines of a transcript still being made, as JSON text like `getTranscript`'s, or null. */
  getPartialTranscript(episodeId: string): Promise<string | null>
  /** Where the words are said in the finished transcripts (see transcriptSearch.ts). */
  searchTranscripts(query: string): Promise<SpokenHit[]>
  /**
   * Which of the Mac's prepared copies to take and which to give back, for the candidates as JSON
   * text (see `PreparedCandidate` in preparedSync.ts); answers JSON text (`PreparedPlan`).
   */
  preparedPlan(candidates: string): Promise<string>
  /**
   * Installs the file at `uri` as the download of the episode when it is the copy the Mac lists for
   * it (the size and the SHA-256 are checked natively). `address` is the episode's audio address,
   * kept as the download's address when it has none. Answers "installed" or why not in one word.
   */
  installPreparedCopy(
    episodeId: string,
    uri: string,
    address: string,
    forListOnly: boolean,
  ): Promise<PreparedInstallAnswer>
  /** Removes the download of a copy taken only for the list; false when it is not such a copy. */
  giveBackPreparedCopy(episodeId: string): Promise<boolean>
  /**
   * Whether prepared copies may be fetched now: on Wi-Fi (the test the automatic downloads use)
   * and not in Low Data Mode. Waits up to a second for the first report of the network.
   */
  isOnWiFi(): Promise<boolean>
  /** Where each transcribed episode's ad finding is. */
  listAds(): Promise<AdsInfo[]>
  /** An episode's saved ads as JSON (`AdsFile` in PodcastAds), or null. */
  getAds(episodeId: string): Promise<string | null>
  getAdSkipSettings(): Promise<AdSkipSettings>
  setAdSkipSettings(
    skipAds: boolean,
    skipOwnPlugs: boolean,
    skipPromos: boolean,
    skipCredits: boolean,
  ): Promise<void>
  /**
   * The Skip ad button: jumps ahead to the end of the ad the phone knows here, or 30 seconds
   * when it knows none (and notes the miss for the Mac). Null when nothing is loaded.
   */
  skipAdNow(): Promise<{ to: number; known: boolean } | null>
  /** The notes not yet sent to the Mac (skips, undos, trims, missed ads), as JSON lines. "" when none. */
  readPendingAdNotes(): Promise<string>
  /**
   * Drops the first `count` pending notes, once they are written to the linked folder, but only
   * the lines whose `at` (milliseconds) is not later than `upToAt`: a note added since the read
   * stays.
   */
  removePendingAdNotes(count: number, upToAt: number): Promise<void>
  /** What the phone skipped, undid, trimmed and missed, per show, as JSON text (see adResults.ts). */
  getAdTally(): Promise<string>
  /** The skip log and the ad finder's diary as text, or null when there is none. */
  readSkipLogText(): Promise<string | null>
  /** Checks a teaching file from the Mac and installs it. True when it was installed. */
  installTeachingFile(
    name: string,
    text: string,
    sha256: string,
  ): Promise<boolean>
  /** Tells the native side which show each feed key is: `{"<feed key>": "<show id>"}`. */
  setTeachingShows(json: string): Promise<void>
  /**
   * Tells the native side which episode is which, so the Mac's marks of the night before find
   * theirs: `{"<episode id>": {"feed": "<feed address>", "guid": "...", "title": "..."}}`.
   */
  setAheadEpisodes(json: string): Promise<void>
  /** What is installed from the Mac, as JSON text (see teaching.ts). */
  getTeachingState(): Promise<string>
  /**
   * Takes back the skip that was just made: back to the ad's start, playing, and the skip is
   * recorded as wrong. False when it is too late.
   */
  undoAdSkip(): Promise<boolean>
  /**
   * The listener's answer to the question that starts at `start` seconds (`onAdAsk`): `isAd`
   * true skips the stretch (like any skip, with Undo), false says it is not an ad. False when
   * no open question starts there.
   */
  answerAdQuestion(
    episodeId: string,
    start: number,
    isAd: boolean,
  ): Promise<boolean>
  /**
   * What silence trimming has saved so far, in seconds of audio, kept in Swift so a stats
   * screen can read it.
   */
  getTrimSavings(): Promise<number>
  /** The listening stats (`ListeningStats` in PodcastPlayback) as a plain object. */
  getStats(): Promise<Record<string, unknown>>
  /** Clears the listening stats. */
  resetStats(): Promise<void>
  /**
   * A copy of the skip log (one line of JSON for each ad skip) that the share sheet can read, as
   * a file address, or null when no skip is logged yet. Nothing is sent by this call.
   */
  exportSkipLog(): Promise<string | null>
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
