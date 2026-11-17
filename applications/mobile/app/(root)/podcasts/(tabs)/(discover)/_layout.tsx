// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { Stack } from "expo-router"

/** This tab's own stack, so a show's page opened here keeps the tab bar. */
export default function TabStackLayout() {
  return <Stack screenOptions={{ headerShown: false }} />
}
