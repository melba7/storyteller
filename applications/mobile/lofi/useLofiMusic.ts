// LOFI-FORK: the lofi music's state and settings, for the player and Settings
// (see FORK.md).
import { useCallback, useEffect, useState } from "react"

import { logger } from "@/logger"
import {
  type LofiImportSummary,
  type LofiMood,
  type LofiMoodOverride,
  type LofiMusicStatus,
  LofiScore,
} from "@/modules/lofi-score"

export type LofiMusic = ReturnType<typeof useLofiMusic>

/**
 * Reads the music's state from the native module, every `pollInterval`
 * milliseconds while mounted (or once, with null), and changes its settings.
 * `available` is false where the module does not exist (Android, the web).
 */
export function useLofiMusic(pollInterval: number | null) {
  const [status, setStatus] = useState<LofiMusicStatus | null>(null)

  const refresh = useCallback(async () => {
    if (!LofiScore) return
    try {
      setStatus(await LofiScore.getStatus())
    } catch (error) {
      logger.error(`Lofi music status: ${String(error)}`)
    }
  }, [])

  useEffect(() => {
    void refresh()
    if (pollInterval === null) return
    const timer = setInterval(() => void refresh(), pollInterval)
    return () => {
      clearInterval(timer)
    }
  }, [refresh, pollInterval])

  const apply = useCallback(
    async (
      optimistic: (current: LofiMusicStatus) => LofiMusicStatus,
      call: () => Promise<LofiMusicStatus> | undefined,
    ) => {
      setStatus((current) => (current ? optimistic(current) : current))
      try {
        const updated = await call()
        if (updated) setStatus(updated)
      } catch (error) {
        logger.error(`Lofi music setting: ${String(error)}`)
        void refresh()
      }
    },
    [refresh],
  )

  const setEnabled = useCallback(
    (enabled: boolean) =>
      apply(
        (current) => ({ ...current, enabled }),
        () => LofiScore?.setEnabled(enabled),
      ),
    [apply],
  )

  const setMutedInCar = useCallback(
    (mutedInCar: boolean) =>
      apply(
        (current) => ({ ...current, mutedInCar }),
        () => LofiScore?.setMutedInCar(mutedInCar),
      ),
    [apply],
  )

  /** The level under the voice in dB, or null for the default. */
  const setMusicLevel = useCallback(
    (level: number | null) =>
      apply(
        (current) => ({
          ...current,
          musicLevelDB: level ?? current.defaultMusicLevelDB,
        }),
        () => LofiScore?.setMusicLevel(level),
      ),
    [apply],
  )

  const setAtmosphereEnabled = useCallback(
    (enabled: boolean) =>
      apply(
        (current) =>
          current.atmosphere
            ? { ...current, atmosphere: { ...current.atmosphere, enabled } }
            : current,
        () => LofiScore?.setAtmosphereEnabled(enabled),
      ),
    [apply],
  )

  /** The atmosphere's level under the voice in dB, or null for the default. */
  const setAtmosphereLevel = useCallback(
    (level: number | null) =>
      apply(
        (current) =>
          current.atmosphere
            ? {
                ...current,
                atmosphere: {
                  ...current.atmosphere,
                  levelDB: level ?? current.atmosphere.defaultLevelDB,
                },
              }
            : current,
        () => LofiScore?.setAtmosphereLevel(level),
      ),
    [apply],
  )

  /** Short narration pauses where the sound swells or hushes. */
  const setAtmospherePauses = useCallback(
    (enabled: boolean) =>
      apply(
        (current) =>
          current.atmosphere
            ? {
                ...current,
                atmosphere: { ...current.atmosphere, pausesEnabled: enabled },
              }
            : current,
        () => LofiScore?.setAtmospherePauses(enabled),
      ),
    [apply],
  )

  /** Music while reading on screen with the narration stopped. */
  const setFollowsReading = useCallback(
    (followsReading: boolean) =>
      apply(
        (current) => ({ ...current, followsReading }),
        () => LofiScore?.setFollowsReading(followsReading),
      ),
    [apply],
  )

  /**
   * The mood playing is wrong: move to `mood`, or to the engine's next guess,
   * and log it for the listening test.
   */
  const markWrongMood = useCallback(
    async (mood: LofiMood | null = null): Promise<LofiMoodOverride | null> => {
      if (!LofiScore) return null
      try {
        const result = await LofiScore.markWrongMood(mood)
        await refresh()
        return result
      } catch (error) {
        logger.error(`Lofi music, wrong mood: ${String(error)}`)
        return null
      }
    },
    [refresh],
  )

  /** The wrong-mood log as text, or null when nothing was marked yet. */
  const getMoodFeedback = useCallback(async (): Promise<string | null> => {
    if (!LofiScore) return null
    return LofiScore.getMoodFeedback()
  }, [])

  const importMusicFolder =
    useCallback(async (): Promise<LofiImportSummary | null> => {
      if (!LofiScore) return null
      const summary = await LofiScore.importMusicFolder()
      await refresh()
      return summary
    }, [refresh])

  const removeImportedMusic = useCallback(
    () =>
      apply(
        (current) => current,
        () => LofiScore?.removeImportedMusic(),
      ),
    [apply],
  )

  return {
    available: LofiScore !== null,
    status,
    refresh,
    setEnabled,
    setMutedInCar,
    setMusicLevel,
    setAtmosphereEnabled,
    setAtmosphereLevel,
    setAtmospherePauses,
    setFollowsReading,
    markWrongMood,
    getMoodFeedback,
    importMusicFolder,
    removeImportedMusic,
  }
}
