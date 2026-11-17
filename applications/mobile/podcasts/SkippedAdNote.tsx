// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { skipNoteText } from "@/modules/podcasts/ads"

import { pressUndo, useSkipNote } from "./useSkipNote"

/** "Skipped ad (1:05)" with an Undo button, for a few seconds after the player skips an ad. */
export function SkippedAdNote() {
  const note = useSkipNote()
  if (note === null) return null
  return (
    <View
      className="w-full flex-row items-center justify-between gap-3 rounded-full bg-white/15 py-1 pr-1 pl-5"
      accessibilityLiveRegion="polite"
    >
      <Text className="text-sm font-medium text-white">
        {skipNoteText(note)}
      </Text>
      <Pressable
        className="rounded-full bg-white px-4 py-2 active:opacity-80"
        accessibilityRole="button"
        accessibilityLabel="Undo the ad skip"
        onPress={pressUndo}
      >
        <Text className="text-sm font-semibold text-black">Undo</Text>
      </Pressable>
    </View>
  )
}
