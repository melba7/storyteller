// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { ScrollView } from "react-native"

import { DiscoverBrowse } from "./DiscoverBrowse"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useStatusBarStyle } from "./usePodcastsTheme"

/**
 * The New tab: what Discover was without its search, which moved to the Search tab. The
 * featured shows, the suggestions "for you", the top chart and the categories.
 */
export function Discover() {
  const statusBarStyle = useStatusBarStyle()
  return (
    <>
      <ScrollView
        className="bg-background flex-1"
        contentContainerStyle={{ paddingBottom: 24 }}
        contentInsetAdjustmentBehavior="automatic"
      >
        <DiscoverBrowse />
      </ScrollView>
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        account
        title="New"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
      />
    </>
  )
}
