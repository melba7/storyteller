// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { Stack } from "expo-router"

/** The tabs, and the player as a screen pushed above them. */
export default function PodcastsLayout() {
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="(tabs)" />
      <Stack.Screen name="player" />
    </Stack>
  )
}
