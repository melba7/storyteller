// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { useMemo } from "react"
import { Pressable, View } from "react-native"
import Swipeable, {
  type SwipeableMethods,
} from "react-native-gesture-handler/ReanimatedSwipeable"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { Podcasts, type UpNextItem } from "@/modules/podcasts/index"
import { formatDuration } from "@/modules/podcasts/library"
import { episodeHref } from "@/modules/podcasts/routes"
import { moveBetween, rowLabel, upNextSummary } from "@/modules/podcasts/upNext"

import { Artwork } from "./Artwork"
import { DragList, type RowAction } from "./DragList"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useEpisodesByIds } from "./hooks"
import { useStatusBarStyle } from "./usePodcastsTheme"
import {
  confirmClear,
  moveQueued,
  moveToEnd,
  removeQueued,
  useUpNext,
} from "./useUpNext"

const ROW_HEIGHT = 76

const ACTIONS: RowAction[] = [
  { name: "playNext", label: "Play next" },
  { name: "playLast", label: "Play last" },
  { name: "remove", label: "Remove" },
]

/**
 * The Up Next tab: the episodes that play after the current one, in order. Drag a row by its
 * handle (or use VoiceOver's Move up and Move down) to reorder; swipe right for Play next
 * and Play last, left for Remove. Tapping a row opens the episode.
 */
export function UpNext() {
  const statusBarStyle = useStatusBarStyle()
  const queue = useUpNext()
  const byId = useMemo(
    () => new Map(queue.map((item) => [item.id, item])),
    [queue],
  )
  const ids = useMemo(() => queue.map((item) => item.id), [queue])
  const episodes = useEpisodesByIds(ids)
  const inLibrary = useMemo(
    () => new Set((episodes.data ?? []).map((episode) => episode.id)),
    [episodes.data],
  )

  function reorder(next: string[]) {
    const move = moveBetween(ids, next)
    if (move) moveQueued(move.from, move.to)
  }

  function act(id: string, name: string) {
    const item = byId.get(id)
    if (!item) return
    if (name === "playNext") moveToEnd(item, "next")
    else if (name === "playLast") moveToEnd(item, "last")
    else if (name === "remove") removeQueued(id)
  }

  return (
    <View className="bg-background flex-1">
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Up Next"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
        right={
          <Stack.Toolbar.Button
            hidden={queue.length === 0}
            accessibilityLabel="Clear Up Next"
            onPress={() => confirmClear(queue.length)}
          >
            Clear
          </Stack.Toolbar.Button>
        }
      />
      {Podcasts === null ? (
        <BelowBar>
          <Message
            title="Up Next needs the iOS app"
            body="This version of the app can't play podcasts."
          />
        </BelowBar>
      ) : queue.length === 0 ? (
        <BelowBar>
          <Message
            title="Nothing in Up Next"
            body="Tap the three dots on an episode, or open it, and choose Play next or Play last. The next episode then starts by itself when the current one ends."
          />
        </BelowBar>
      ) : (
        <>
          <DragList
            header={
              <Text
                className="text-muted-foreground py-2 text-sm"
                accessibilityLabel={upNextSummary(queue)}
              >
                {upNextSummary(queue)}
              </Text>
            }
            ids={ids}
            rowHeight={ROW_HEIGHT}
            onChange={reorder}
            label={(id, index, count) => {
              const item = byId.get(id)
              return item ? rowLabel(item, index, count) : ""
            }}
            actions={ACTIONS}
            onAction={act}
            renderContent={(id) => {
              const item = byId.get(id)
              return item ? (
                <QueueRow item={item} openable={inLibrary.has(id)} />
              ) : null
            }}
          />
        </>
      )}
    </View>
  )
}

function QueueRow({ item, openable }: { item: UpNextItem; openable: boolean }) {
  const router = useRouter()
  const segments = useSegments()
  const left =
    item.duration && item.duration > item.position
      ? formatDuration(item.duration - item.position)
      : ""
  const details = [item.showTitle, left === "" ? "" : `${left} left`]
    .filter((part) => part !== "")
    .join(" · ")

  function playNext(methods: SwipeableMethods) {
    methods.close()
    moveToEnd(item, "next")
  }
  function playLast(methods: SwipeableMethods) {
    methods.close()
    moveToEnd(item, "last")
  }
  function remove(methods: SwipeableMethods) {
    methods.close()
    removeQueued(item.id)
  }

  return (
    <Swipeable
      renderLeftActions={(_progress, _translation, methods) => (
        <View className="flex-row">
          <Button
            className="h-full w-20 rounded-none"
            accessibilityLabel={`Play ${item.title} next`}
            onPress={() => playNext(methods)}
          >
            <Text className="text-xs">Play next</Text>
          </Button>
          <Button
            variant="secondary"
            className="h-full w-20 rounded-none"
            accessibilityLabel={`Play ${item.title} last`}
            onPress={() => playLast(methods)}
          >
            <Text className="text-xs">Play last</Text>
          </Button>
        </View>
      )}
      renderRightActions={(_progress, _translation, methods) => (
        <Button
          variant="destructive"
          className="h-full w-20 rounded-none"
          accessibilityLabel={`Remove ${item.title} from Up Next`}
          onPress={() => remove(methods)}
        >
          <Text className="text-xs">Remove</Text>
        </Button>
      )}
    >
      <Pressable
        className="bg-background active:bg-secondary h-full flex-row items-center gap-3"
        accessibilityRole="button"
        accessibilityLabel={`${item.title}. ${details}`}
        disabled={!openable}
        onPress={() => router.push(episodeHref(segments, item.id))}
      >
        <Artwork uri={item.artworkUrl ?? null} size={52} />
        <View className="flex-1 gap-1">
          <Text className="font-semibold" numberOfLines={2}>
            {item.title}
          </Text>
          {details ? (
            <Text className="text-muted-foreground text-sm" numberOfLines={1}>
              {details}
            </Text>
          ) : null}
        </View>
      </Pressable>
    </Swipeable>
  )
}

function Message({ title, body }: { title: string; body: string }) {
  return (
    <View className="items-center gap-2 px-8 py-12">
      <Text className="text-center font-semibold">{title}</Text>
      <Text className="text-muted-foreground text-center text-sm">{body}</Text>
    </View>
  )
}
