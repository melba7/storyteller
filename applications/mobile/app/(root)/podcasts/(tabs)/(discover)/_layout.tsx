// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { TabStack } from "@/podcasts/TabStack"

// The tab opens on Discover itself. Without this the stack's first screen would be the
// shared show preview, whose name sorts first, and it opened with no show to read.
export const unstable_settings = { anchor: "discover" }

export default function TabStackLayout() {
  return <TabStack />
}
