// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { skipNoteBackLabels, skipNoteText } from "@/modules/podcasts/ads"

import { useSheet } from "./playerSheetContext"
import { pressBack, pressUndo, useSkipNote } from "./useSkipNote"

/**
 * "Skipped ad (1:05)" with Undo (it was no ad) and Back 10 s (the skip went too far), for a few
 * seconds after the player skips an ad.
 */
export function SkippedAdNote() {
  const note = useSkipNote()
  const sheet = useSheet()
  if (note === null) return null
  const back = skipNoteBackLabels()
  return (
    <View
      className="w-full flex-row items-center justify-between gap-3 rounded-full py-1 pr-1 pl-5"
      style={{ backgroundColor: sheet.rest }}
      accessibilityLiveRegion="polite"
    >
      <Text
        className="flex-1 text-sm font-medium"
        style={{ color: sheet.ink }}
        numberOfLines={1}
      >
        {skipNoteText(note)}
      </Text>
      <View className="flex-row items-center gap-1">
        <Pressable
          className="rounded-full px-3 py-2 active:opacity-80"
          accessibilityRole="button"
          accessibilityLabel={back.accessibility}
          onPress={pressBack}
        >
          <Text className="text-sm font-semibold" style={{ color: sheet.ink }}>
            {back.text}
          </Text>
        </Pressable>
        <Pressable
          className="rounded-full px-4 py-2 active:opacity-80"
          style={{ backgroundColor: sheet.ink }}
          accessibilityRole="button"
          accessibilityLabel="Undo the ad skip"
          onPress={pressUndo}
        >
          <Text className="text-sm font-semibold" style={{ color: sheet.top }}>
            Undo
          </Text>
        </Pressable>
      </View>
    </View>
  )
}
