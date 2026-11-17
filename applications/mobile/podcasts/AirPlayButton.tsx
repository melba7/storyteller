// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { View } from "react-native"

import { AirPlayView } from "@/modules/podcasts/airPlayView"
import { isLightSheet } from "@/modules/podcasts/playerSheet"

import { useSheet } from "./playerSheetContext"

/** The AirPlay button in the player's bottom row: iOS's own list of speakers. */
export function AirPlayButton() {
  const sheet = useSheet()
  if (AirPlayView === null) return null
  return (
    <View className="h-11 items-center justify-center">
      <AirPlayView
        label="AirPlay, choose a speaker or headphones"
        light={isLightSheet(sheet.top)}
        style={{ width: 28, height: 28 }}
      />
    </View>
  )
}
