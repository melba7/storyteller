// LOFI-FORK: the podcasts section's screens (see FORK.md).
import AsyncStorage from "@react-native-async-storage/async-storage"
import { useCallback, useEffect, useRef, useState } from "react"

import {
  DEFAULT_VIEW,
  type LibraryView,
  parseLibraryView,
  serializeLibraryView,
} from "@/modules/podcasts/libraryView"

const STORAGE_KEY = "podcasts.libraryView"

async function readSaved(): Promise<LibraryView> {
  try {
    return parseLibraryView(await AsyncStorage.getItem(STORAGE_KEY))
  } catch {
    return DEFAULT_VIEW
  }
}

async function save(view: LibraryView): Promise<void> {
  try {
    await AsyncStorage.setItem(STORAGE_KEY, serializeLibraryView(view))
  } catch (cause) {
    // The choice still applies until the app closes; only keeping it failed.
    console.warn("Couldn't save the library view", cause)
  }
}

/**
 * The library's layout and order, kept on the phone. `view` is null until the saved choice
 * has been read, so the screen does not flash the default first. A failure to read or save
 * never breaks the screen.
 */
export function useLibraryView(): {
  view: LibraryView | null
  change: (patch: Partial<LibraryView>) => void
} {
  const [view, setView] = useState<LibraryView | null>(null)
  const latest = useRef<LibraryView | null>(null)

  useEffect(() => {
    let current = true
    readSaved().then((saved) => {
      // A choice made before the read finished wins.
      if (current && latest.current === null) {
        latest.current = saved
        setView(saved)
      }
    })
    return () => {
      current = false
    }
  }, [])

  const change = useCallback((patch: Partial<LibraryView>) => {
    const next = { ...(latest.current ?? DEFAULT_VIEW), ...patch }
    latest.current = next
    setView(next)
    void save(next)
  }, [])

  return { view, change }
}
