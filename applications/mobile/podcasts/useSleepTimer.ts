// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState, useSyncExternalStore } from "react"
import { Alert } from "react-native"

import { Podcasts, type SleepTimerState } from "@/modules/podcasts/index"
import { readableError } from "@/modules/podcasts/nativeError"
import { NO_SLEEP_TIMER, readSleepState } from "@/modules/podcasts/sleepTimer"

// What the screens know about the sleep timer: read once from Swift, then kept fresh by its
// onSleepTimerChange event. One copy is shared by every screen.
let current: SleepTimerState = NO_SLEEP_TIMER
let started = false
const listeners = new Set<() => void>()

function publish(next: SleepTimerState) {
  current = next
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  // Listening comes first, so a change during the first read is not lost.
  Podcasts.addListener("onSleepTimerChange", (state) =>
    publish(readSleepState(state)),
  )
  Podcasts.getSleepTimer().then(
    (state) => publish(readSleepState(state)),
    () => {
      started = false
    },
  )
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** The sleep timer as Swift has it. */
export function useSleepTimer(): SleepTimerState {
  return useSyncExternalStore(subscribe, () => current)
}

/** The time now, read again every second while `running`. */
export function useNow(running: boolean): number {
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    if (!running) return
    setNow(Date.now())
    const handle = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(handle)
  }, [running])
  return now
}

function run(action: Promise<void> | undefined) {
  action?.catch((cause: unknown) =>
    Alert.alert("Sleep timer", readableError(cause)),
  )
}

export const sleepTimer = {
  startMinutes: (minutes: number) => run(Podcasts?.startSleepTimer(minutes)),
  endOfEpisode: () => run(Podcasts?.sleepUntilEndOfEpisode()),
  addFiveMinutes: () => run(Podcasts?.extendSleepTimer()),
  cancel: () => run(Podcasts?.cancelSleepTimer()),
}
