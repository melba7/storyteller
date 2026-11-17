// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { View } from "react-native"

import { SleepTimerButton } from "./SleepTimerSheet"

/** The row of small buttons under the speed button: the sleep timer, and more as they come. */
export function PlayerButtons() {
  return (
    <View className="w-full flex-row flex-wrap items-center justify-center gap-3">
      <SleepTimerButton />
    </View>
  )
}
