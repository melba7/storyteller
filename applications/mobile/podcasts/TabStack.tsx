// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"
import { useCSSVariable } from "uniwind"

/**
 * A tab's own stack, so a show's page opened here keeps the tab bar. Every screen gets the
 * native iOS 26 header (transparent, no shadow, a back button without its label), which
 * `ScreenBar` fills in with the title and buttons. The status bar text is set by each tab
 * root's `<StatusBar>`, not here: the native `statusBarStyle` option needs a setting that
 * Expo turns off. An episode opens as a sheet over the tab, with a grabber and two heights
 * (about half the screen, and nearly full), and has no header. The route's name here is its
 * path inside the tab's group.
 */
export function TabStack() {
  const tint = useCSSVariable("--color-primary") as string
  const background = useCSSVariable("--color-background") as string
  return (
    <Stack
      screenOptions={{
        headerShown: true,
        headerTransparent: true,
        headerShadowVisible: false,
        headerBackButtonDisplayMode: "minimal",
        headerTintColor: tint,
        // Nothing white behind a list while it loads or bounces.
        contentStyle: { backgroundColor: background },
      }}
    >
      <Stack.Screen
        name="episode/[id]"
        options={{
          headerShown: false,
          presentation: "formSheet",
          sheetAllowedDetents: [0.6, 1],
          sheetInitialDetentIndex: 0,
          sheetGrabberVisible: true,
        }}
      />
    </Stack>
  )
}
