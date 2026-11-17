// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { View } from "react-native"

import { Text } from "@/components/ui/text"
import {
  describeStatus,
  useAppleSyncStatus,
} from "@/modules/podcasts/appleStatus"

import { ROW } from "./SettingsGroup"

/**
 * One row for the Apple Podcasts follow list: what the last read of the Mac's file found, such
 * as "64 shows found, read 5 min ago", or why it found nothing ("File not downloaded yet",
 * "Folder not linked"). Put it in a `SettingsGroup`.
 */
export function AppleSyncStatus() {
  const status = useAppleSyncStatus()
  const problem = !status.reading && status.problem !== null
  return (
    <View className={`${ROW} py-3`}>
      <Text className="font-semibold">Apple Podcasts follow list</Text>
      <Text
        className={
          problem ? "text-destructive text-sm" : "text-muted-foreground text-sm"
        }
      >
        {describeStatus(status, Date.now())}
      </Text>
    </View>
  )
}
