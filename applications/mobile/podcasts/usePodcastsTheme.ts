// LOFI-FORK: the podcasts section's themes (see FORK.md).
import AsyncStorage from "@react-native-async-storage/async-storage"
import { useCallback, useEffect, useSyncExternalStore } from "react"
import { useColorScheme } from "react-native"
import { useUniwind } from "uniwind"

import {
  DEFAULT_CHOICE,
  type ThemeChoice,
  isDarkTheme,
  parseChoice,
  resolveThemeName,
  serializeChoice,
} from "@/modules/podcasts/theme"

const KEY = "podcasts.theme"

// One copy of the choice for the whole section, so Profile and the layout stay in step.
let current: ThemeChoice = DEFAULT_CHOICE
let loading: Promise<void> | null = null
const listeners = new Set<() => void>()

function set(choice: ThemeChoice) {
  current = choice
  listeners.forEach((listener) => listener())
}

function load(): Promise<void> {
  loading ??= AsyncStorage.getItem(KEY).then(
    (saved) => set(parseChoice(saved)),
    () => {}, // Unreadable: keep following the app.
  )
  return loading
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/**
 * The Podcasts section's theme: the saved choice, the Uniwind theme name it comes to now and
 * `setChoice` to change it. The choice is saved in AsyncStorage under one key.
 */
export function usePodcastsTheme() {
  const choice = useSyncExternalStore(
    subscribe,
    () => current,
    () => DEFAULT_CHOICE,
  )
  // The rest of the app's light or dark. Only meaningful above the section's wrapper, which is
  // where the name is used; Profile below it only needs the choice.
  const { theme: app } = useUniwind()
  const system = useColorScheme()

  useEffect(() => {
    load()
  }, [])

  const setChoice = useCallback((patch: Partial<ThemeChoice>) => {
    const before = current
    set({ ...before, ...patch })
    AsyncStorage.setItem(KEY, serializeChoice(current)).catch(() => set(before))
  }, [])

  const name = resolveThemeName(
    choice,
    app === "dark" ? "dark" : "light",
    system === "dark" || system === "light" ? system : null,
  )
  return { choice, name, dark: isDarkTheme(name), setChoice }
}
