// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"
import { useCSSVariable } from "uniwind"

/**
 * A tab's own stack, so a show's page opened here keeps the tab bar. Every screen gets the
 * native iOS 26 header (transparent, no shadow, a back button without its label), which
 * `ScreenBar` fills in with the title and buttons. The status bar text is set by each tab
 * root's `<StatusBar>`, not here: the native `statusBarStyle` option needs a setting that
 * Expo turns off. Every screen, an episode's page too, is a plain push in this stack.
 */
export function TabStack() {
  const tint = useCSSVariable("--color-foreground") as string
  const background = useCSSVariable("--color-background") as string
  return (
    <Stack
      screenOptions={{
        headerShown: true,
        headerTransparent: true,
        headerShadowVisible: false,
        headerBackButtonDisplayMode: "minimal",
        // The bar's glyphs are label-coloured, drawn in glass; purple is for in-content accents.
        headerTintColor: tint,
        // Nothing white behind a list while it loads or bounces.
        contentStyle: { backgroundColor: background },
      }}
    />
  )
}
