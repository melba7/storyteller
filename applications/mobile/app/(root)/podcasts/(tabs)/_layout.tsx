// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { NativeTabs } from "expo-router/native-tabs"
import { useCSSVariable } from "uniwind"

import { MiniPlayerContent, useHasMiniPlayer } from "@/podcasts/MiniPlayer"

/**
 * The Podcasts section's tab bar (iOS 26's native one), which shrinks when a list scrolls
 * down. The mini player sits in the bar's accessory, above the tabs, once an episode is loaded. Each tab has its own stack (Home, New, Library and the system Search tab). The icons
 * and labels take the section's theme colours; NativeTabs has no prop for a dark or light bar,
 * and on iOS 26 the system draws the bar's glass itself, so only the tint can follow the theme.
 */
export default function PodcastTabsLayout() {
  const hasMiniPlayer = useHasMiniPlayer()
  const tint = useCSSVariable("--color-primary") as string
  const quiet = useCSSVariable("--color-muted-foreground") as string
  return (
    <NativeTabs
      tintColor={tint}
      minimizeBehavior="onScrollDown"
      iconColor={{ default: quiet, selected: tint }}
      labelStyle={{ default: { color: quiet }, selected: { color: tint } }}
    >
      <NativeTabs.Trigger name="(home)">
        <NativeTabs.Trigger.Label>Home</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="house.fill" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(new)">
        <NativeTabs.Trigger.Label>New</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="square.grid.2x2.fill" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(library)">
        <NativeTabs.Trigger.Label>Library</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="square.stack.fill" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(search)" role="search">
        <NativeTabs.Trigger.Label>Search</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="magnifyingglass" />
      </NativeTabs.Trigger>
      {hasMiniPlayer ? (
        <NativeTabs.BottomAccessory>
          <MiniPlayerContent />
        </NativeTabs.BottomAccessory>
      ) : null}
    </NativeTabs>
  )
}
