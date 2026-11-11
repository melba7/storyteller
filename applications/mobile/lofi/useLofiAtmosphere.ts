// LOFI-FORK: the atmosphere's state and settings, for the player's panel and
// Settings (see FORK.md).
import { useCallback, useEffect, useState } from "react"

import { logger } from "@/logger"
import {
  type LofiImportSummary,
  type LofiStatus,
  type LofiSyncSummary,
  LofiScore,
} from "@/modules/lofi-score"

export type LofiAtmosphere = ReturnType<typeof useLofiAtmosphere>

/**
 * Reads the atmosphere's state from the native module, every `pollInterval`
 * milliseconds while mounted (or once, with null), and changes its settings.
 * `available` is false where the module does not exist (Android, the web).
 */
export function useLofiAtmosphere(pollInterval: number | null) {
  const [status, setStatus] = useState<LofiStatus | null>(null)

  const refresh = useCallback(async () => {
    if (!LofiScore) return
    try {
      setStatus(await LofiScore.getStatus())
    } catch (error) {
      logger.error(`Lofi atmosphere status: ${String(error)}`)
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
      optimistic: (current: LofiStatus) => LofiStatus,
      call: () => Promise<LofiStatus> | undefined,
    ) => {
      setStatus((current) => (current ? optimistic(current) : current))
      try {
        const updated = await call()
        if (updated) setStatus(updated)
      } catch (error) {
        logger.error(`Lofi atmosphere setting: ${String(error)}`)
        void refresh()
      }
    },
    [refresh],
  )

  const setMutedInCar = useCallback(
    (mutedInCar: boolean) =>
      apply(
        (current) => ({ ...current, mutedInCar }),
        () => LofiScore?.setMutedInCar(mutedInCar),
      ),
    [apply],
  )

  const setEnabled = useCallback(
    (enabled: boolean) =>
      apply(
        (current) => ({
          ...current,
          atmosphere: { ...current.atmosphere, enabled },
        }),
        () => LofiScore?.setAtmosphereEnabled(enabled),
      ),
    [apply],
  )

  /** The sounds' level under the voice in dB, or null for the default. */
  const setLevel = useCallback(
    (level: number | null) =>
      apply(
        (current) => ({
          ...current,
          atmosphere: {
            ...current.atmosphere,
            levelDB: level ?? current.atmosphere.defaultLevelDB,
          },
        }),
        () => LofiScore?.setAtmosphereLevel(level),
      ),
    [apply],
  )

  /** How much is going on in the atmosphere, 0 to 1, or null for the default. */
  const setIntensity = useCallback(
    (intensity: number | null) =>
      apply(
        (current) => ({
          ...current,
          atmosphere: {
            ...current.atmosphere,
            intensity: intensity ?? current.atmosphere.defaultIntensity,
          },
        }),
        () => LofiScore?.setAtmosphereIntensity(intensity),
      ),
    [apply],
  )

  /** Short narration pauses where the sound swells or hushes. */
  const setPauses = useCallback(
    (enabled: boolean) =>
      apply(
        (current) => ({
          ...current,
          atmosphere: { ...current.atmosphere, pausesEnabled: enabled },
        }),
        () => LofiScore?.setAtmospherePauses(enabled),
      ),
    [apply],
  )

  /** One-off sounds (a knock, a clap of thunder) on their sentences. */
  const setOneShots = useCallback(
    (enabled: boolean) =>
      apply(
        (current) => ({
          ...current,
          atmosphere: { ...current.atmosphere, oneShotsEnabled: enabled },
        }),
        () => LofiScore?.setAtmosphereOneShots(enabled),
      ),
    [apply],
  )

  /** The sounds while reading on screen with the narration stopped. */
  const setFollowsReading = useCallback(
    (followsReading: boolean) =>
      apply(
        (current) => ({ ...current, followsReading }),
        () => LofiScore?.setFollowsReading(followsReading),
      ),
    [apply],
  )

  const importSoundsFolder =
    useCallback(async (): Promise<LofiImportSummary | null> => {
      if (!LofiScore) return null
      const summary = await LofiScore.importSoundsFolder()
      await refresh()
      return summary
    }, [refresh])

  /** Copies what is new in the linked folder now; null when none is linked. */
  const syncSoundsFolder =
    useCallback(async (): Promise<LofiSyncSummary | null> => {
      if (!LofiScore) return null
      try {
        return await LofiScore.syncSoundsFolder()
      } finally {
        await refresh()
      }
    }, [refresh])

  const unlinkSoundsFolder = useCallback(
    () =>
      apply(
        (current) => {
          const { linkedFolder: _unlinked, ...folder } = current.folder
          return { ...current, folder }
        },
        () => LofiScore?.unlinkSoundsFolder(),
      ),
    [apply],
  )

  const removeImportedSounds = useCallback(
    () =>
      apply(
        (current) => current,
        () => LofiScore?.removeImportedSounds(),
      ),
    [apply],
  )

  return {
    available: LofiScore !== null,
    status,
    refresh,
    setMutedInCar,
    setEnabled,
    setLevel,
    setIntensity,
    setPauses,
    setOneShots,
    setFollowsReading,
    importSoundsFolder,
    syncSoundsFolder,
    unlinkSoundsFolder,
    removeImportedSounds,
  }
}
