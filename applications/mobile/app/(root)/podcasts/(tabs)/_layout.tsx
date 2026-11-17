// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { NativeTabs } from "expo-router/native-tabs"
import { useCSSVariable } from "uniwind"

import { upNextBadge } from "@/modules/podcasts/upNext"
import { MiniPlayerContent, useHasMiniPlayer } from "@/podcasts/MiniPlayer"
import { useUpNext } from "@/podcasts/useUpNext"

/**
 * The Podcasts section's tab bar (iOS 26's native one). The tab bar shrinks when a list scrolls down. The mini player sits in the bar's
 * accessory, above the tabs, once an episode is loaded. Each tab has its own stack. The icons
 * and labels take the section's theme colours; NativeTabs has no prop for a dark or light bar,
 * and on iOS 26 the system draws the bar's glass itself, so only the tint can follow the theme.
 */
export default function PodcastTabsLayout() {
  const hasMiniPlayer = useHasMiniPlayer()
  const badge = upNextBadge(useUpNext())
  const tint = useCSSVariable("--color-primary") as string
  const quiet = useCSSVariable("--color-muted-foreground") as string
  return (
    <NativeTabs
      tintColor={tint}
      minimizeBehavior="onScrollDown"
      iconColor={{ default: quiet, selected: tint }}
      labelStyle={{ default: { color: quiet }, selected: { color: tint } }}
    >
      <NativeTabs.Trigger name="(library)">
        <NativeTabs.Trigger.Label>Podcasts</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="square.grid.2x2" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(playlists)">
        <NativeTabs.Trigger.Label>Playlists</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="music.note.list" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(discover)">
        <NativeTabs.Trigger.Label>Discover</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="magnifyingglass" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(upnext)">
        <NativeTabs.Trigger.Label>Up Next</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="text.line.first.and.arrowtriangle.forward" />
        <NativeTabs.Trigger.Badge hidden={badge === ""}>
          {badge}
        </NativeTabs.Trigger.Badge>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(profile)">
        <NativeTabs.Trigger.Label>Profile</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="person.crop.circle" />
      </NativeTabs.Trigger>
      {hasMiniPlayer ? (
        <NativeTabs.BottomAccessory>
          <MiniPlayerContent />
        </NativeTabs.BottomAccessory>
      ) : null}
    </NativeTabs>
  )
}
