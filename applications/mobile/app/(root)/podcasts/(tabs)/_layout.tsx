// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { NativeTabs } from "expo-router/native-tabs"

import { MiniPlayerContent, useHasMiniPlayer } from "@/podcasts/MiniPlayer"

/**
 * The Podcasts section's tab bar (iOS 26's native one). The mini player sits in the bar's
 * accessory, above the tabs, once an episode is loaded. Each tab has its own stack.
 */
export default function PodcastTabsLayout() {
  const hasMiniPlayer = useHasMiniPlayer()
  return (
    <NativeTabs>
      <NativeTabs.Trigger name="(library)">
        <NativeTabs.Trigger.Label>Podcasts</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="square.grid.2x2" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(discover)">
        <NativeTabs.Trigger.Label>Discover</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="magnifyingglass" />
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
