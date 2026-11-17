// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { View } from "react-native"

import { usePlayerValue, player } from "@/modules/podcasts/playerInstance"
import { placeShare } from "@/modules/podcasts/share"

import { AirPlayButton } from "./AirPlayButton"
import { LibraryButtons } from "./LibraryButtons"
import { ShareButton } from "./ShareButton"
import { SleepTimerButton } from "./SleepTimerSheet"

/** The row of small buttons under the speed button: the sleep timer, AirPlay and share, and more as they come. */
export function PlayerButtons() {
  const sharable = usePlayerValue((view) => view.episode !== null)
  return (
    <View className="w-full flex-row flex-wrap items-center justify-center gap-3">
      <SleepTimerButton />
      <AirPlayButton />
      <LibraryButtons />
      {sharable ? (
        <ShareButton
          look="player"
          label="Share this place in the episode"
          build={() => {
            const { episode, show, position } = player.getView()
            return episode ? placeShare(episode, show, position) : null
          }}
        />
      ) : null}
    </View>
  )
}
