import { useGlobalSearchParams } from "expo-router"
import { View } from "react-native"

import { groupedScreenClass } from "@/apple-look/GroupedList"
import { SpeedMenuContent } from "@/components/toolbarItems/SpeedItem"
import {
  readerFormSheetBottomPadding,
  readerFormSheetGrabberHeight,
  useReaderFormSheetBottomInset,
} from "@/components/toolbarItems/readerFormSheetLayout"
import { type UUID } from "@/uuid"

type SpeedMenuParams = {
  uuid?: UUID
}

export default function SpeedMenuScreen() {
  const { uuid } = useGlobalSearchParams<SpeedMenuParams>()
  const bottomInset = useReaderFormSheetBottomInset()

  return (
    <View
      className={`${groupedScreenClass} overflow-hidden`}
      style={{ marginBottom: -bottomInset, paddingBottom: bottomInset }}
    >
      <View
        className="items-center justify-center"
        style={{ height: readerFormSheetGrabberHeight }}
      >
        <View className="bg-muted-foreground/40 h-1 w-12 rounded-full" />
      </View>
      <SpeedMenuContent bookUuid={uuid} />
      <View style={{ height: readerFormSheetBottomPadding }} />
    </View>
  )
}
