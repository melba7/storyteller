// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { View } from "react-native"

import { AirPlayView } from "@/modules/podcasts/airPlayView"

/** The AirPlay button in the player's row of small buttons: iOS's own list of speakers. */
export function AirPlayButton() {
  if (AirPlayView === null) return null
  return (
    <View className="size-11 items-center justify-center rounded-full bg-white/15">
      <AirPlayView
        label="AirPlay, choose a speaker or headphones"
        style={{ width: 28, height: 28 }}
      />
    </View>
  )
}
