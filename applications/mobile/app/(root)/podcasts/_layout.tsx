// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { Stack } from "expo-router"
import type { ComponentProps } from "react"
import { ScopedTheme, useCSSVariable } from "uniwind"

import { playerLeaving, playerStayed } from "@/modules/podcasts/playerGate"
import { usePodcastsTheme } from "@/podcasts/usePodcastsTheme"

// The generated uniwind-types.d.ts only lists light and dark until Metro runs with the extra
// themes from metro.config.js, so the name is cast.
type ThemeName = ComponentProps<typeof ScopedTheme>["theme"]

/**
 * The tabs, the account sheet (Profile) and the player as sheets that slides up over them and swipes down. Everything in
 * the section, the sheets and the mini player too, takes its colours from the listener's chosen
 * theme (Profile > Appearance) because the whole section sits inside one ScopedTheme.
 */
export default function PodcastsLayout() {
  const { name } = usePodcastsTheme()
  return (
    <ScopedTheme theme={name as ThemeName}>
      <ThemedStack />
    </ScopedTheme>
  )
}

/**
 * What the player's sheet tells the player gate (modules/podcasts/playerGate.ts): a swipe down
 * has started, and that swipe was cancelled. A tap on the mini player while the sheet slides
 * away is then remembered, and opens the player once the sheet is gone, instead of stacking
 * another sheet on one that is leaving. (A cancelled swipe sends `gestureCancel`: the sheet's
 * own `transitionEnd` is not sent for it.)
 */
const playerListeners = {
  transitionStart: (event: { data: { closing: boolean } }) => {
    if (event.data.closing) playerLeaving()
  },
  gestureCancel: () => playerStayed(),
}

/** The stack, with the theme's background behind the screens while they slide. */
function ThemedStack() {
  const background = useCSSVariable("--color-background") as string
  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: background },
      }}
    >
      <Stack.Screen name="(tabs)" />
      {/* One player at a time: a second push finds the route that is already there. */}
      <Stack.Screen
        name="player"
        dangerouslySingular
        options={{ presentation: "modal" }}
        listeners={playerListeners}
      />
      <Stack.Screen name="account" options={{ presentation: "modal" }} />
    </Stack>
  )
}
