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
} from "./index"
import type { Show, StoredEpisode } from "./library"
import {
  SAVE_EVERY_MS,
  clampPosition,
  clampSpeed,
  isPlayed,
  resumeStart,
} from "./playbackRules"

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
  savePlayback(
    episodeId: string,
    position: number,
    played: boolean,
  ): Promise<void>
  saveArtworkColor(showId: string, color: string): Promise<void>
  lastPlayedEpisode(): Promise<StoredEpisode | null>
  getShow(id: string): Promise<Show | null>
  getEpisode(id: string): Promise<StoredEpisode | null>
  setInterval(callback: () => void, ms: number): unknown
  clearInterval(handle: unknown): void
  /** The listener's "mark played when this many seconds are left" (0 or missing: off). */
  playedWithin?(): number
  /** Reports a failure that has no screen to show it (saving the place). */
  report?(cause: unknown): void
}

export function createPlayback(deps: PlaybackDeps) {
  let view = EMPTY_VIEW
  let timer: unknown = null
  let listening = false
  const listeners = new Set<() => void>()
  /** The loaded episode is inside the "mark played" window and was saved as played. */
  let markedEarly = false

  function set(next: Partial<PlayerView>) {
    view = { ...view, ...next }
    for (const listener of listeners) listener()
  }

  /** Keeps the place. A failure to save must not stop the playing. */
  function persist(position: number, reachedEnd = false) {
    const episode = view.episode
    if (!episode) return
    const played = isPlayed(
      position,
      view.duration,
      reachedEnd,
      deps.playedWithin?.() ?? 0,
    )
    deps.savePlayback(episode.id, position, played).catch((cause: unknown) => {
      deps.report?.(cause)
    })
  }

  function syncTimer() {
    if (view.isPlaying && timer === null) {
      timer = deps.setInterval(() => persist(view.position), SAVE_EVERY_MS)
    } else if (!view.isPlaying && timer !== null) {
      deps.clearInterval(timer)
      timer = null
    }
  }

  function onState(state: PlaybackState) {
    const episode = view.episode
    if (!episode || state.episodeId !== episode.id) return
    const wasPlaying = view.isPlaying
    set({
      loaded: true,
      position: state.position,
      duration: state.duration ?? view.duration,
      isPlaying: state.isPlaying,
      isBuffering: state.isBuffering,
      rate: state.rate,
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
    if (event.episodeId !== view.episode?.id) return
    set({ position: event.position, isPlaying: false, isBuffering: false })
    persist(event.position, true)
    syncTimer()
  }

  /** Swift started the next queued episode (the one before ended): follow along. */
  async function onAdvanced(event: PlaybackAdvanced) {
    try {
      const episode = await deps.getEpisode(event.episodeId)
      if (!episode) return
      const show = await deps.getShow(episode.showId)
      // One that was still playing (the next button on the headphones) keeps its place.
      if (view.episode && view.isPlaying) persist(view.position)
      markedEarly = false
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

  function onError(event: PlaybackError) {
    if (event.episodeId !== view.episode?.id) return
    set({ error: event.message, isPlaying: false, isBuffering: false })
    syncTimer()
  }

  function listen() {
    if (listening || !deps.native) return
    listening = true
    deps.native.addListener("onPlaybackState", onState)
    deps.native.addListener("onPlaybackEnded", onEnded)
    deps.native.addListener("onPlaybackError", onError)
    deps.native.addListener("onPlaybackAdvanced", (event) => {
      void onAdvanced(event)
    })
  }

  /** Works out the show's artwork colour once, and keeps it. */
  async function tintFor(show: Show) {
    if (!deps.native || show.artworkColor || !show.imageUrl) return
    const color = await deps.native.artworkColor(show.imageUrl)
    if (!color) return
    await deps.saveArtworkColor(show.id, color)
    if (view.show?.id === show.id) {
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
      if (!view.isPlaying) await run(() => native().play())
      return
    }
    if (view.episode && view.loaded) persist(view.position)
    markedEarly = false
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
      error: null,
    })
    await run(() =>
      native().load({
        episodeId: episode.id,
        url: episode.audioUrl,
        title: episode.title,
        showTitle: show?.title ?? "",
        artworkUrl: episode.imageUrl ?? show?.imageUrl ?? null,
        savedPosition: episode.positionSeconds,
        duration: episode.durationSeconds,
        played: episode.played,
        autoplay: true,
        audioType: episode.audioType,
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

  /** Play or pause. An episode only remembered after a restart is loaded first. */
  async function togglePlayPause() {
    const { episode, show, loaded, isPlaying } = view
    if (!episode) return
    if (!loaded) return playEpisode(episode, show)
    if (isPlaying) await run(() => native().pause())
    else await run(() => native().play())
  }

  async function seekTo(seconds: number) {
    if (!view.loaded) return
    const target = clampPosition(seconds, view.duration)
    set({ position: target })
    await run(() => native().seekTo(target))
    persist(target)
  }

  async function skip(seconds: number) {
    if (!view.loaded) return
    const target = clampPosition(view.position + seconds, view.duration)
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

  return {
    getView: () => view,
    subscribe(listener: () => void) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    restoreLast,
    playEpisode,
    playFrom,
    togglePlayPause,
    seekTo,
    skip,
    setRate,
  }
}

export type Playback = ReturnType<typeof createPlayback>
