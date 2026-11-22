// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { View } from "react-native"

import { Text } from "@/components/ui/text"

import { useSheet } from "./playerSheetContext"
import { useMissedNote } from "./useMissedNote"

/** "Jumped 30 seconds. Noted as a missed ad.", in the style of the skipped-ad note. */
export function MissedAdNote() {
  const note = useMissedNote()
  const sheet = useSheet()
  if (note === null) return null
  return (
    <View
      className="w-full justify-center rounded-full px-5 py-3"
      style={{ backgroundColor: sheet.rest }}
      accessibilityLiveRegion="polite"
    >
      <Text
        className="text-sm font-medium"
        style={{ color: sheet.ink }}
        numberOfLines={2}
      >
        {note.text}
      </Text>
    </View>
  )
}
