// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Trash2 } from "lucide-react-native"
import { useMemo } from "react"
import { Pressable, View } from "react-native"
import Swipeable, {
  type SwipeableMethods,
} from "react-native-gesture-handler/ReanimatedSwipeable"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { type UpNextItem } from "@/modules/podcasts/index"
import { formatDuration } from "@/modules/podcasts/library"
import { moveBetween } from "@/modules/podcasts/upNext"

import { Artwork } from "./Artwork"
import { DragList } from "./DragList"
import { PanelTitle } from "./PlayerPages"
import { pick } from "./haptics"
import { useSheet } from "./playerSheetContext"
import { confirmClear, moveQueued, removeQueued, useUpNext } from "./useUpNext"

const ROW_HEIGHT = 64
const ART = 48

function details(item: UpNextItem): string {
  const left =
    item.duration && item.duration > item.position
      ? formatDuration(item.duration - item.position)
      : ""
  return [item.showTitle, left === "" ? "" : `${left} left`]
    .filter((part) => part !== "")
    .join(" · ")
}

/**
 * "Playing Next", in place of the artwork: the Up Next queue with its rows dragged by their
 * handles, swiped left to remove, and a Clear button. It shares its data with the Up Next page.
 */
export function PlayerQueue() {
  const sheet = useSheet()
  const queue = useUpNext()
  const byId = useMemo(
    () => new Map(queue.map((item) => [item.id, item])),
    [queue],
  )
  const ids = useMemo(() => queue.map((item) => item.id), [queue])

  function reorder(next: string[]) {
    const move = moveBetween(ids, next)
    if (move) moveQueued(move.from, move.to)
  }

  return (
    <View className="flex-1">
      <PanelTitle
        title="Playing Next"
        right={
          queue.length === 0 ? undefined : (
            <Pressable
              className="min-h-11 justify-center px-2 active:opacity-60"
              accessibilityRole="button"
              accessibilityLabel="Clear Up Next"
              onPress={() => confirmClear(queue.length)}
            >
              <Text className="font-semibold" style={{ color: sheet.tint }}>
                Clear
              </Text>
            </Pressable>
          )
        }
      />
      {queue.length === 0 ? (
        <Text className="px-1 text-base" style={{ color: sheet.tint }}>
          {
            'Nothing is queued. Choose Play next or Play last in an episode\'s "..." menu.'
          }
        </Text>
      ) : (
        // The list draws itself with the section's theme colours, so it sits on the sheet as a card.
        <View className="flex-1 overflow-hidden rounded-2xl">
          <DragList
            ids={ids}
            rowHeight={ROW_HEIGHT}
            onChange={reorder}
            onDrop={pick}
            label={(id, index, count) => {
              const item = byId.get(id)
              return item
                ? `${item.title}. ${details(item)}. ${index + 1} of ${count}`
                : ""
            }}
            actions={[{ name: "remove", label: "Remove" }]}
            onAction={(id, name) => {
              if (name === "remove") removeQueued(id)
            }}
            renderContent={(id) => {
              const item = byId.get(id)
              return item ? <QueueRow item={item} /> : null
            }}
          />
        </View>
      )}
    </View>
  )
}

function QueueRow({ item }: { item: UpNextItem }) {
  function remove(methods: SwipeableMethods) {
    pick()
    methods.close()
    removeQueued(item.id)
  }
  const line = details(item)
  return (
    <Swipeable
      renderRightActions={(_progress, _translation, methods) => (
        <Button
          variant="destructive"
          className="h-full w-20 flex-col gap-1 rounded-none"
          accessibilityLabel={`Remove ${item.title} from Up Next`}
          onPress={() => remove(methods)}
        >
          <Icon as={Trash2} size={20} className="text-white" />
          <Text className="text-xs">Remove</Text>
        </Button>
      )}
    >
      <View className="bg-background h-full flex-row items-center gap-3 pl-2">
        <Artwork
          uri={item.artworkUrl ?? null}
          size={ART}
          className="rounded-lg"
        />
        <View className="flex-1">
          <Text className="font-semibold" numberOfLines={2}>
            {item.title}
          </Text>
          {line === "" ? null : (
            <Text className="text-muted-foreground text-sm" numberOfLines={1}>
              {line}
            </Text>
          )}
        </View>
      </View>
    </Swipeable>
  )
}
