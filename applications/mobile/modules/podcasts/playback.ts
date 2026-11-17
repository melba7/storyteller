// LOFI-FORK: the podcasts section's player controller (see FORK.md).
//
// The app's side of playing: which episode is loaded, what the native player last said, and
// keeping the listener's place in the library. The native module is handed in, so the rules
// here (when the place is saved, when an episode counts as played) are tested without it.
// playerInstance.ts wires it to the real module and database.
import type {
  PlaybackEnded,
  PlaybackError,
  PlaybackLoadOptions,
  PlaybackState,
  PodcastsEvents,
} from "./index"
import type { Show, StoredEpisode } from "./library"

// MARK: Rules (the same numbers as PodcastKit's PodcastPlayback)

export const SKIP_BACK_SECONDS = 10
export const SKIP_AHEAD_SECONDS = 45
export const SAVE_EVERY_MS = 15_000
const PLAYED_WITHIN_SECONDS = 5
const RESTART_WITHIN_SECONDS = 10

/** "0:05", "12:34", "1:02:03". Not a number or negative reads as "0:00". */
export function formatTime(seconds: number): string {
  const whole = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0
  const hours = Math.floor(whole / 3600)
  const minutes = Math.floor((whole % 3600) / 60)
  const rest = String(whole % 60).padStart(2, "0")
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${rest}`
    : `${minutes}:${rest}`
}

/** "-12:34", the time left as Pocket Casts shows it. "--:--" when the length is unknown. */
export function timeLeft(position: number, duration: number | null): string {
  if (duration === null || !Number.isFinite(duration) || duration <= 0) {
    return "--:--"
  }
  return `-${formatTime(Math.max(0, duration - position))}`
}

/** "1.0x", "1.5x". */
export function speedLabel(rate: number): string {
  return `${rate.toFixed(1)}x`
}

/** The speed one step (0.1) up or down, kept inside 0.5x to 3.0x. */
export function stepSpeed(rate: number, direction: 1 | -1): number {
  return clampSpeed(rate + direction * 0.1)
}

export function clampSpeed(rate: number): number {
  if (!Number.isFinite(rate)) return 1
  return Math.min(3, Math.max(0.5, Math.round(rate * 10) / 10))
}

/** 0 for a played episode or one with under 10 seconds left; otherwise the saved place. */
export function resumeStart(
  saved: number,
  duration: number | null,
  played: boolean,
): number {
  if (played || !Number.isFinite(saved) || saved <= 0) return 0
  if (duration !== null && duration > 0) {
    if (saved >= duration || duration - saved < RESTART_WITHIN_SECONDS) return 0
  }
  return saved
}

/** Played to its end, or stopped within 5 seconds of the end. */
export function isPlayed(
  position: number,
  duration: number | null,
  reachedEnd: boolean,
): boolean {
  if (reachedEnd) return true
  if (duration === null || !(duration > 0)) return false
  return duration - position <= PLAYED_WITHIN_SECONDS
}

/** The mini player shows when an episode is loaded or one was played before. */
export function showsMiniPlayer(
  loaded: StoredEpisode | null,
  lastPlayed: StoredEpisode | null,
): boolean {
  return loaded !== null || lastPlayed !== null
}

/** A position kept inside the episode (only 0 is a limit while the length is unknown). */
export function clampPosition(position: number, duration: number | null) {
  const floor = Math.max(0, Number.isFinite(position) ? position : 0)
  return duration !== null && duration > 0 ? Math.min(floor, duration) : floor
}

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
  setInterval(callback: () => void, ms: number): unknown
  clearInterval(handle: unknown): void
  /** Reports a failure that has no screen to show it (saving the place). */
  report?(cause: unknown): void
}

export function createPlayback(deps: PlaybackDeps) {
  let view = EMPTY_VIEW
  let timer: unknown = null
  let listening = false
  const listeners = new Set<() => void>()

  function set(next: Partial<PlayerView>) {
    view = { ...view, ...next }
    for (const listener of listeners) listener()
  }

  /** Keeps the place. A failure to save must not stop the playing. */
  function persist(position: number, reachedEnd = false) {
    const episode = view.episode
    if (!episode) return
    const played = isPlayed(position, view.duration, reachedEnd)
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
    syncTimer()
  }

  function onEnded(event: PlaybackEnded) {
    if (event.episodeId !== view.episode?.id) return
    set({ position: event.position, isPlaying: false, isBuffering: false })
    persist(event.position, true)
    syncTimer()
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
      }),
    )
    if (show) tintFor(show).catch(() => {})
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
    togglePlayPause,
    seekTo,
    skip,
    setRate,
  }
}

export type Playback = ReturnType<typeof createPlayback>
