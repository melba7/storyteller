// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Trash2 } from "lucide-react-native"
import { useMemo } from "react"
import { Alert, Pressable, View } from "react-native"
import Swipeable, {
  type SwipeableMethods,
} from "react-native-gesture-handler/ReanimatedSwipeable"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { getEpisode, getShow } from "@/modules/podcasts/db"
import { type UpNextItem } from "@/modules/podcasts/index"
import { formatDuration } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { player } from "@/modules/podcasts/playerInstance"
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
        // The rows are drawn on the sheet itself, in the sheet's colours, like the transcript.
        <View className="flex-1">
          <DragList
            onSheet={{ line: sheet.rest, grip: sheet.muted }}
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
            actions={[
              { name: "play", label: "Play now" },
              { name: "remove", label: "Remove" },
            ]}
            onAction={(id, name) => {
              if (name === "remove") removeQueued(id)
              else if (name === "play") {
                const item = byId.get(id)
                if (item) void playQueued(item)
              }
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

/** Plays a queued episode now; Swift takes it out of the queue as it starts. */
async function playQueued(item: UpNextItem) {
  try {
    const episode = await getEpisode(item.id)
    if (!episode) throw new Error("This episode is no longer in your library.")
    const show = episode.showId ? await getShow(episode.showId) : null
    await player.playEpisode(episode, show)
  } catch (cause) {
    Alert.alert("Couldn't play the episode", readableError(cause))
  }
}

function QueueRow({ item }: { item: UpNextItem }) {
  const sheet = useSheet()
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
          className="h-full w-20 flex-col gap-1 rounded-none px-1"
          accessibilityLabel={`Remove ${item.title} from Up Next`}
          onPress={() => remove(methods)}
        >
          <Icon as={Trash2} size={20} className="text-white" />
          <Text className="text-xs">Remove</Text>
        </Button>
      )}
    >
      <Pressable
        className="h-full flex-row items-center gap-3 active:opacity-60"
        accessibilityRole="button"
        accessibilityLabel={`Play ${item.title} now`}
        onPress={() => {
          pick()
          void playQueued(item)
        }}
      >
        <Artwork
          uri={item.artworkUrl ?? null}
          size={ART}
          className="rounded-lg"
        />
        <View className="flex-1">
          <Text
            className="font-semibold"
            style={{ color: sheet.ink }}
            numberOfLines={2}
          >
            {item.title}
          </Text>
          {line === "" ? null : (
            <Text
              className="text-sm"
              style={{ color: sheet.muted }}
              numberOfLines={1}
            >
              {line}
            </Text>
          )}
        </View>
      </Pressable>
    </Swipeable>
  )
}
