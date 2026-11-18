import { ensureArtworkColor } from "./artworkColor"
// LOFI-FORK: the podcasts section's player controller (see FORK.md).
//
// The app's side of playing: which episode is loaded, what the native player last said, and
// keeping the listener's place in the library. The native module is handed in, so the rules
// here (when the place is saved, when an episode counts as played) are tested without it.
// playerInstance.ts wires it to the real module and database.
import type {
  PlaybackAdvanced,
  PlaybackEnded,
  PlaybackError,
  PlaybackLoadOptions,
  PlaybackState,
  PodcastsEvents,
  UpNextChange,
  UpNextItem,
} from "./index"
import type { Show, StoredEpisode } from "./library"
import {
  SAVE_EVERY_MS,
  clampPosition,
  clampSpeed,
  type ListenSave,
  isPlayed,
  resumeStart,
  shouldNotifyListen,
} from "./playbackRules"
import { isPreviewId } from "./preview"

// MARK: Controller

export type PlayerView = {
  episode: StoredEpisode | null
  show: Show | null
  /** The native player has this episode (false for one only remembered after a restart). */
  loaded: boolean
  position: number
  duration: number | null
  isPlaying: boolean
  isBuffering: boolean
  rate: number
  /** The native player plays the plain address, so no ad is skipped. */
  streamsPlain: boolean
  /** Play waits a moment for the first look at the start of a stream. */
  checkingStart: boolean
  error: string | null
}

export const EMPTY_VIEW: PlayerView = {
  episode: null,
  show: null,
  loaded: false,
  position: 0,
  duration: null,
  isPlaying: false,
  isBuffering: false,
  rate: 1,
  streamsPlain: false,
  checkingStart: false,
  error: null,
}

export interface NativePlayer {
  load(options: PlaybackLoadOptions): Promise<void>
  play(): Promise<void>
  pause(): Promise<void>
  togglePlayPause(): Promise<void>
  seekTo(seconds: number): Promise<void>
  skipBy(seconds: number): Promise<void>
  setRate(rate: number): Promise<number>
  artworkColor(url: string): Promise<string | null>
  addListener<E extends keyof PodcastsEvents>(
    event: E,
    listener: PodcastsEvents[E],
  ): { remove(): void }
}

export interface PlaybackDeps {
  /** Null where there is no native player (Android, the web). */
  native: NativePlayer | null
  /** `notify` says whether the lists should read the library again (see `shouldNotifyListen`). */
  savePlayback(
    episodeId: string,
    position: number,
    played: boolean,
    notify: boolean,
  ): Promise<void>
  saveArtworkColor(showId: string, color: string): Promise<void>
  lastPlayedEpisode(): Promise<StoredEpisode | null>
  getShow(id: string): Promise<Show | null>
  getEpisode(id: string): Promise<StoredEpisode | null>
  setInterval(callback: () => void, ms: number): unknown
  clearInterval(handle: unknown): void
  /** The listener's "mark played when this many seconds are left" (0 or missing: off). */
  playedWithin?(): number
  /**
   * Asked when a different episode starts to play (not on a resume): should it play from its
   * own download as the bytes arrive (so ads can be skipped in it)? It is asked before the
   * episode loads; a play pressed meanwhile wins. An answer that fails means "no".
   */
  playThroughDownload?(
    episode: StoredEpisode,
    show: Show | null,
  ): Promise<boolean> | boolean
  /** Reports a failure that has no screen to show it (saving the place). */
  report?(cause: unknown): void
}

/** How many Up Next items the controller remembers, for episodes the library lacks. */
const KNOWN_QUEUE_ITEMS = 200

/** An episode built from its Up Next item, for one the library has no row for. */
export function episodeFromQueueItem(item: UpNextItem): StoredEpisode {
  return {
    id: item.id,
    showId: item.showId ?? "",
    guid: item.id,
    title: item.title,
    publishedAt: 0,
    durationSeconds: item.duration ?? null,
    notes: "",
    audioUrl: item.url,
    audioType: item.type,
    audioBytes: null,
    imageUrl: item.artworkUrl ?? null,
    season: null,
    number: null,
    transcriptUrl: null,
    transcriptType: null,
    people: [],
    chaptersUrl: item.chaptersUrl ?? null,
    positionSeconds: item.position,
    played: false,
    lastPlayedAt: null,
    archived: false,
    starredAt: null,
  }
}

export function createPlayback(deps: PlaybackDeps) {
  let view = EMPTY_VIEW
  let timer: unknown = null
  let listening = false
  const listeners = new Set<() => void>()
  /** The loaded episode is inside the "mark played" window and was saved as played. */
  let markedEarly = false
  /** The listener marked the loaded episode played, so the next save keeps it played. */
  let markedPlayed = false
  /** The last save the lists were told about (see `shouldNotifyListen`). */
  let told: ListenSave | null = null
  /** The id the native player knows the loaded episode by (a followed preview keeps its old one). */
  let nativeId: string | null = null
  /** Counts the plays that load an episode, so one that was deciding can see it was replaced. */
  let playTurn = 0
  /** Every Up Next item seen lately: Swift drops one from its queue before it announces it. */
  const knownItems = new Map<string, UpNextItem>()

  function set(next: Partial<PlayerView>) {
    view = { ...view, ...next }
    for (const listener of listeners) listener()
  }

  /**
   * Keeps the place. A failure to save must not stop the playing. A `timed` save (the 15
   * second clock) tells the lists only when what they show could have changed.
   */
  function persist(position: number, reachedEnd = false, timed = false) {
    const episode = view.episode
    if (!episode) return
    const played =
      markedPlayed ||
      isPlayed(position, view.duration, reachedEnd, deps.playedWithin?.() ?? 0)
    const save = { episodeId: episode.id, position, played }
    const notify = shouldNotifyListen(told, save, timed)
    if (notify) told = save
    deps
      .savePlayback(episode.id, position, played, notify)
      .catch((cause: unknown) => {
        deps.report?.(cause)
      })
  }

  function syncTimer() {
    if (view.isPlaying && timer === null) {
      timer = deps.setInterval(
        () => persist(view.position, false, true),
        SAVE_EVERY_MS,
      )
    } else if (!view.isPlaying && timer !== null) {
      deps.clearInterval(timer)
      timer = null
    }
  }

  function onState(state: PlaybackState) {
    const episode = view.episode
    if (!episode || state.episodeId !== (nativeId ?? episode.id)) return
    const wasPlaying = view.isPlaying
    set({
      loaded: true,
      position: state.position,
      duration: state.duration ?? view.duration,
      isPlaying: state.isPlaying,
      isBuffering: state.isBuffering,
      rate: state.rate,
      streamsPlain: state.streamsPlain === true,
      checkingStart: state.checkingStart === true,
      error: state.isPlaying ? null : view.error,
    })
    if (wasPlaying && !state.isPlaying && !state.isBuffering) {
      persist(state.position)
    }
    markEarly(state.position)
    syncTimer()
  }

  /** Saves the episode as played the moment it enters the listener's "N seconds left" window. */
  function markEarly(position: number) {
    const within = deps.playedWithin?.() ?? 0
    const inside =
      within > 0 && isPlayed(position, view.duration, false, within)
    if (inside && !markedEarly) persist(position)
    markedEarly = inside
  }

  function onEnded(event: PlaybackEnded) {
    if (!view.episode || event.episodeId !== (nativeId ?? view.episode.id))
      return
    set({ position: event.position, isPlaying: false, isBuffering: false })
    persist(event.position, true)
    syncTimer()
  }

  /** Swift started the next queued episode (the one before ended): follow along. */
  async function onAdvanced(event: PlaybackAdvanced) {
    try {
      const item = knownItems.get(event.episodeId)
      const episode =
        (await deps.getEpisode(event.episodeId)) ??
        (item ? episodeFromQueueItem(item) : null)
      if (!episode) return
      const show = await deps.getShow(episode.showId)
      // One that was still playing (the next button on the headphones) keeps its place.
      if (view.episode && view.isPlaying) persist(view.position)
      markedEarly = false
      markedPlayed = false
      nativeId = episode.id
      set({
        episode,
        show,
        loaded: true,
        position: resumeStart(
          episode.positionSeconds,
          episode.durationSeconds,
          false,
        ),
        duration: episode.durationSeconds,
        isPlaying: false,
        isBuffering: true,
        error: null,
      })
      if (show) tintFor(show).catch(() => {})
    } catch (cause) {
      deps.report?.(cause)
    }
  }

  function onQueue(change: UpNextChange) {
    for (const item of change.items) {
      knownItems.delete(item.id)
      knownItems.set(item.id, item)
    }
    while (knownItems.size > KNOWN_QUEUE_ITEMS) {
      const oldest = knownItems.keys().next().value
      if (oldest === undefined) break
      knownItems.delete(oldest)
    }
  }

  function onError(event: PlaybackError) {
    if (!view.episode || event.episodeId !== (nativeId ?? view.episode.id))
      return
    set({ error: event.message, isPlaying: false, isBuffering: false })
    syncTimer()
  }

  function listen() {
    if (listening || !deps.native) return
    listening = true
    deps.native.addListener("onPlaybackState", onState)
    deps.native.addListener("onPlaybackEnded", onEnded)
    deps.native.addListener("onPlaybackError", onError)
    deps.native.addListener("onUpNextChange", onQueue)
    deps.native.addListener("onPlaybackAdvanced", (event) => {
      void onAdvanced(event)
    })
  }

  /** Works out the show's artwork colour once, and keeps it. */
  async function tintFor(show: Show) {
    const { native } = deps
    const color = await ensureArtworkColor(
      show,
      native
        ? {
            measure: (url) => native.artworkColor(url),
            save: deps.saveArtworkColor,
          }
        : null,
    )
    if (color && view.show?.id === show.id && !view.show.artworkColor) {
      set({ show: { ...view.show, artworkColor: color } })
    }
  }

  function native(): NativePlayer {
    if (!deps.native) throw new Error("Podcasts need the iOS app.")
    return deps.native
  }

  async function run(action: () => Promise<unknown>) {
    try {
      await action()
    } catch (cause) {
      set({
        error: cause instanceof Error ? cause.message : "Playback failed.",
        isPlaying: false,
        isBuffering: false,
      })
    }
  }

  /** After the app starts: remember the last episode, so the mini player can show it. */
  async function restoreLast() {
    if (view.episode) return
    const episode = await deps.lastPlayedEpisode()
    if (!episode || view.episode) return
    const show = await deps.getShow(episode.showId)
    if (view.episode) return
    set({
      episode,
      show,
      position: resumeStart(
        episode.positionSeconds,
        episode.durationSeconds,
        episode.played,
      ),
      duration: episode.durationSeconds,
    })
  }

  /** Starts the episode, at its saved place. The same episode again resumes it. */
  async function playEpisode(episode: StoredEpisode, show: Show | null) {
    if (!deps.native) {
      set({ error: "Podcasts need the iOS app." })
      return
    }
    listen()
    if (view.episode?.id === episode.id && view.loaded) {
      playTurn++
      if (!view.isPlaying) await run(() => native().play())
      return
    }
    const turn = ++playTurn
    let throughDownload = false
    try {
      throughDownload =
        (await deps.playThroughDownload?.(episode, show)) ?? false
    } catch (cause) {
      deps.report?.(cause)
    }
    // A newer play pressed while this one was deciding wins.
    if (turn !== playTurn) return
    if (view.episode && view.loaded) persist(view.position)
    markedEarly = false
    markedPlayed = false
    nativeId = episode.id
    set({
      episode,
      show,
      loaded: false,
      position: resumeStart(
        episode.positionSeconds,
        episode.durationSeconds,
        episode.played,
      ),
      duration: episode.durationSeconds,
      isPlaying: false,
      isBuffering: true,
      streamsPlain: false,
      checkingStart: false,
      error: null,
    })
    await run(() =>
      native().load({
        episodeId: episode.id,
        showId: episode.showId,
        url: episode.audioUrl,
        title: episode.title,
        showTitle: show?.title ?? "",
        artworkUrl: episode.imageUrl ?? show?.imageUrl ?? null,
        savedPosition: episode.positionSeconds,
        duration: episode.durationSeconds,
        played: episode.played,
        autoplay: true,
        audioType: episode.audioType,
        chaptersUrl: episode.chaptersUrl,
        playThroughDownload: throughDownload,
        language: show?.language ?? null,
        notes: episode.notes,
        showLink: show?.link ?? null,
      }),
    )
    if (show) tintFor(show).catch(() => {})
  }

  /** Plays the episode from this second (an ad's start): a loaded one seeks, else it loads there. */
  async function playFrom(
    episode: StoredEpisode,
    show: Show | null,
    seconds: number,
  ) {
    if (view.episode?.id === episode.id && view.loaded) {
      await seekTo(seconds)
      if (!view.isPlaying) await run(() => native().play())
      return
    }
    await playEpisode(
      { ...episode, positionSeconds: Math.max(0, seconds), played: false },
      show,
    )
  }

  /**
   * Plays, and never pauses: for a tap that means "play from here" (a chapter, a transcript
   * line). An episode only remembered after a restart is loaded first.
   */
  async function play() {
    const { episode, show, loaded, isPlaying } = view
    if (!episode) return
    if (!loaded) return playEpisode(episode, show)
    if (!isPlaying) await run(() => native().play())
  }

  /**
   * Play or pause. A stream that is still loading pauses too, so it does not start by itself
   * when the network is back. The short wait for a stream's first look is the exception: a
   * second Play ends that wait.
   */
  async function togglePlayPause() {
    const { loaded, isPlaying, isBuffering, checkingStart } = view
    if (loaded && (isPlaying || (isBuffering && !checkingStart))) {
      await run(() => native().pause())
    } else {
      await play()
    }
  }

  /** Before the first Play: remembers the place and starts there when the episode loads. */
  function moveUnloaded(target: number) {
    const episode = view.episode
    if (!episode) return
    set({
      position: target,
      episode: { ...episode, positionSeconds: target, played: false },
    })
    persist(target)
  }

  async function seekTo(seconds: number) {
    const target = clampPosition(seconds, view.duration)
    if (!view.loaded) return moveUnloaded(target)
    set({ position: target })
    await run(() => native().seekTo(target))
    persist(target)
  }

  async function skip(seconds: number) {
    const target = clampPosition(view.position + seconds, view.duration)
    if (!view.loaded) return moveUnloaded(target)
    set({ position: target })
    await run(() => native().skipBy(seconds))
    persist(target)
  }

  async function setRate(rate: number) {
    const wanted = clampSpeed(rate)
    set({ rate: wanted })
    if (!deps.native) return
    await run(async () => {
      set({ rate: await native().setRate(wanted) })
    })
  }

  /**
   * The listener marked episodes played or unplayed. The loaded one keeps the mark through the
   * player's next save; unplayed also puts it back at the start.
   */
  async function episodesMarked(ids: readonly string[], played: boolean) {
    const episode = view.episode
    if (!episode || !ids.includes(episode.id)) return
    markedPlayed = played
    markedEarly = false
    set({ episode: { ...episode, played } })
    if (!played) await seekTo(0)
  }

  /** A followed show's episodes are in the library: a playing preview episode becomes its twin. */
  function adoptLibrary(episodes: readonly StoredEpisode[], show: Show | null) {
    const current = view.episode
    if (!current || !isPreviewId(current.id)) return
    const twin = episodes.find((e) => e.guid === current.guid)
    if (!twin) return
    markedPlayed = false
    set({
      episode: { ...twin, positionSeconds: view.position },
      show: show ?? view.show,
    })
    persist(view.position)
  }

  /** After a library change (a rename): the loaded episode's title and picture are read again. */
  async function refreshEpisode() {
    const current = view.episode
    if (!current || isPreviewId(current.id)) return
    try {
      const fresh = await deps.getEpisode(current.id)
      if (!fresh || view.episode?.id !== current.id) return
      if (fresh.title === current.title && fresh.imageUrl === current.imageUrl)
        return
      set({
        episode: {
          ...view.episode,
          title: fresh.title,
          imageUrl: fresh.imageUrl,
        },
      })
    } catch (cause) {
      deps.report?.(cause)
    }
  }

  return {
    getView: () => view,
    episodesMarked,
    adoptLibrary,
    refreshEpisode,
    subscribe(listener: () => void) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    restoreLast,
    playEpisode,
    playFrom,
    play,
    togglePlayPause,
    seekTo,
    skip,
    setRate,
  }
}

export type Playback = ReturnType<typeof createPlayback>
