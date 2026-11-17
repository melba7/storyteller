import { Undo2Icon, X } from "lucide-react-native"
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { clearReturnPosition, returnToPreviousPosition } from "@/store/actions"
import { useAppDispatch, useAppSelector } from "@/store/appState"
import { getReturnToPosition } from "@/store/selectors/bookshelfSelectors"
import { type UUID } from "@/uuid"

export function NavigationReturnControl({
  bookUuid,
  onReturn,
}: {
  bookUuid?: UUID | undefined
  onReturn?: (() => void) | undefined
}) {
  const dispatch = useAppDispatch()
  const returnPosition = useAppSelector((state) =>
    bookUuid ? getReturnToPosition(state, bookUuid) : null,
  )

  if (!bookUuid || !returnPosition) return null

  return (
    <View className="border-border bg-background min-h-11 flex-row items-center gap-1 border-b px-2">
      <Button
        accessibilityLabel="Back to previous position"
        className="h-9 flex-1 justify-start px-2"
        onPress={() => {
          dispatch(
            returnToPreviousPosition({
              bookUuid,
              timestamp: Date.now(),
            }),
          )
          onReturn?.()
        }}
        variant="ghost"
      >
        <Icon
          as={Undo2Icon}
          size={16}
          className="text-primary"
        />
        <Text className="text-[15px] font-semibold text-primary">
          Back to previous position
        </Text>
      </Button>
      <Button
        accessibilityLabel="Dismiss return to previous position"
        className="h-9 w-9"
        hitSlop={12}
        onPress={() => {
          dispatch(clearReturnPosition({ bookUuid }))
        }}
        size="icon"
        variant="ghost"
      >
        <Icon as={X} size={16} className="text-primary" />
      </Button>
    </View>
  )
}
