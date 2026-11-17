// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"

/**
 * A tab's own stack, so a show's page opened here keeps the tab bar. An episode opens as a
 * sheet over the tab, with a grabber and two heights (about half the screen, and nearly
 * full). The route's name here is its path inside the tab's group.
 */
export function TabStack() {
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen
        name="episode/[id]"
        options={{
          presentation: "formSheet",
          sheetAllowedDetents: [0.6, 1],
          sheetInitialDetentIndex: 0,
          sheetGrabberVisible: true,
        }}
      />
    </Stack>
  )
}
