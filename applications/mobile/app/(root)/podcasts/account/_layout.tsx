// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { Stack } from "expo-router"
import { useCSSVariable } from "uniwind"

/**
 * The account sheet's own stack: Profile, and Stats pushed inside it. The sheet is presented
 * as a modal by the section's layout; the screens use the same transparent native header as
 * the tabs.
 */
export default function AccountLayout() {
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
        contentStyle: { backgroundColor: background },
      }}
    />
  )
}
