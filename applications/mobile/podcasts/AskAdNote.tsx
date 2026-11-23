// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import {
  ASK_NOTE_TEXT,
  ASK_NO_ACCESSIBILITY,
  ASK_NO_LABEL,
  ASK_YES_ACCESSIBILITY,
  ASK_YES_LABEL,
} from "@/modules/podcasts/askNote"
import type { SheetColors } from "@/modules/podcasts/playerSheet"

import { useSheet } from "./playerSheetContext"
import { pressAskAnswer, useAskNote } from "./useAskNote"

/**
 * "Ad? Skip" with Skip (it is an ad) and Not an ad, while the playhead is in a stretch the phone
 * is not sure about. In the style of the skipped-ad note.
 */
export function AskAdNote() {
  const note = useAskNote()
  const sheet = useSheet()
  if (note === null) return null
  return <AskAdNoteView sheet={sheet} onAnswer={pressAskAnswer} />
}

/** The note itself, for the sheet's colours; `onAnswer` gets true for Skip and false for Not an ad. */
export function AskAdNoteView({
  sheet,
  onAnswer,
}: {
  sheet: SheetColors
  onAnswer: (isAd: boolean) => void
}) {
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
        {ASK_NOTE_TEXT}
      </Text>
      <View className="flex-row items-center gap-1">
        <Pressable
          className="rounded-full px-3 py-2 active:opacity-80"
          accessibilityRole="button"
          accessibilityLabel={ASK_NO_ACCESSIBILITY}
          onPress={() => onAnswer(false)}
        >
          <Text className="text-sm font-semibold" style={{ color: sheet.ink }}>
            {ASK_NO_LABEL}
          </Text>
        </Pressable>
        <Pressable
          className="rounded-full px-4 py-2 active:opacity-80"
          style={{ backgroundColor: sheet.ink }}
          accessibilityRole="button"
          accessibilityLabel={ASK_YES_ACCESSIBILITY}
          onPress={() => onAnswer(true)}
        >
          <Text className="text-sm font-semibold" style={{ color: sheet.top }}>
            {ASK_YES_LABEL}
          </Text>
        </Pressable>
      </View>
    </View>
  )
}
