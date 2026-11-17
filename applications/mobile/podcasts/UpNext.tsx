// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import {
  ArrowDownToLine,
  ArrowUpToLine,
  ListEnd,
  Trash2,
} from "lucide-react-native"
import { useMemo } from "react"
import { Pressable, View } from "react-native"
import Swipeable, {
  type SwipeableMethods,
} from "react-native-gesture-handler/ReanimatedSwipeable"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { Podcasts, type UpNextItem } from "@/modules/podcasts/index"
import { formatDuration } from "@/modules/podcasts/library"
import { SEARCH_HREF, episodeHref } from "@/modules/podcasts/routes"
import {
  moveBetween,
  progressFraction,
  rowLabel,
  upNextSummary,
} from "@/modules/podcasts/upNext"

import { Artwork } from "./Artwork"
import { DragList, type RowAction } from "./DragList"
import { EmptyState } from "./EmptyState"
import { EpisodeRow } from "./EpisodeRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { pick } from "./haptics"
import { useEpisodesByIds, useShows } from "./hooks"
import { useUpNextShelf } from "./useHome"
import { useStatusBarStyle } from "./usePodcastsTheme"
import {
  confirmClear,
  moveQueued,
  moveToEnd,
  removeQueued,
  useUpNext,
} from "./useUpNext"

const ROW_HEIGHT = 76
const ART = 56

const ACTIONS: RowAction[] = [
  { name: "playNext", label: "Play next" },
  { name: "playLast", label: "Play last" },
  { name: "remove", label: "Remove" },
]

/**
 * The Up Next page (Home's "Up Next >" and Library's Up Next row): the episodes that play after the current one, in order. Drag a row by its
 * handle (or use VoiceOver's Move up and Move down) to reorder; swipe right for Play next
 * and Play last, left for Remove. Tapping a row opens the episode.
 */
export function UpNext() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const queue = useUpNext()
  const byId = useMemo(
    () => new Map(queue.map((item) => [item.id, item])),
    [queue],
  )
  const ids = useMemo(() => queue.map((item) => item.id), [queue])
  const episodes = useEpisodesByIds(ids)
  const shelf = useUpNextShelf().data ?? []
  const shows = useShows()
  const showById = useMemo(
    () => new Map((shows.data ?? []).map((show) => [show.id, show])),
    [shows.data],
  )
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
    pick()
    if (name === "playNext") moveToEnd(item, "next")
    else if (name === "playLast") moveToEnd(item, "last")
    else if (name === "remove") removeQueued(id)
  }

  return (
    <>
      {Podcasts === null ? (
        <BelowBar>
          <EmptyState
            icon={ListEnd}
            title="Up Next needs the iOS app"
            body="This version of the app can't play podcasts."
          />
        </BelowBar>
      ) : queue.length === 0 && shelf.length === 0 ? (
        <BelowBar>
          <EmptyState
            icon={ListEnd}
            title="Nothing in Up Next"
            body="Tap the three dots on an episode, or open it, and choose Play next or Play last. The next episode then starts by itself when the current one ends."
            action={{
              label: "Find an episode",
              onPress: () => router.navigate(SEARCH_HREF),
            }}
          />
        </BelowBar>
      ) : (
        <DragList
          header={
            <View className="gap-1 pt-2 pb-2">
              <Text className="text-2xl font-bold" accessibilityRole="header">
                Playing Next
              </Text>
              <Text
                className="text-muted-foreground text-sm"
                accessibilityLabel={
                  queue.length === 0 ? undefined : upNextSummary(queue)
                }
              >
                {queue.length === 0
                  ? "Nothing queued. Choose Play Next or Play Last from an episode's menu."
                  : upNextSummary(queue)}
              </Text>
            </View>
          }
          footer={
            shelf.length > 0 ? (
              <View className="pt-6 pb-6">
                <Text className="text-2xl font-bold" accessibilityRole="header">
                  Next from your shows
                </Text>
                {shelf.map(({ episode }) => {
                  const show = showById.get(episode.showId)
                  return show ? (
                    <EpisodeRow
                      key={episode.id}
                      artwork
                      episode={episode}
                      show={show}
                    />
                  ) : null
                })}
              </View>
            ) : null
          }
          ids={ids}
          rowHeight={ROW_HEIGHT}
          onChange={reorder}
          onDrop={pick}
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
      )}
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Up Next"
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
    </>
  )
}

function QueueRow({ item, openable }: { item: UpNextItem; openable: boolean }) {
  const router = useRouter()
  const segments = useSegments()
  const left =
    item.duration && item.duration > item.position
      ? formatDuration(item.duration - item.position)
      : ""
  const progress = progressFraction(item.position, item.duration)
  const details = [item.showTitle, left === "" ? "" : `${left} left`]
    .filter((part) => part !== "")
    .join(" · ")

  function playNext(methods: SwipeableMethods) {
    pick()
    methods.close()
    moveToEnd(item, "next")
  }
  function playLast(methods: SwipeableMethods) {
    pick()
    methods.close()
    moveToEnd(item, "last")
  }
  function remove(methods: SwipeableMethods) {
    pick()
    methods.close()
    removeQueued(item.id)
  }

  return (
    <Swipeable
      renderLeftActions={(_progress, _translation, methods) => (
        <View className="flex-row">
          <Button
            className="h-full w-20 flex-col gap-1 rounded-none"
            accessibilityLabel={`Play ${item.title} next`}
            onPress={() => playNext(methods)}
          >
            <Icon
              as={ArrowUpToLine}
              size={20}
              className="text-primary-foreground"
            />
            <Text className="text-xs">Play next</Text>
          </Button>
          <Button
            variant="secondary"
            className="h-full w-20 flex-col gap-1 rounded-none"
            accessibilityLabel={`Play ${item.title} last`}
            onPress={() => playLast(methods)}
          >
            <Icon
              as={ArrowDownToLine}
              size={20}
              className="text-secondary-foreground"
            />
            <Text className="text-xs">Play last</Text>
          </Button>
        </View>
      )}
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
      <Pressable
        className="bg-background active:bg-secondary h-full flex-row items-center gap-3"
        accessibilityRole="button"
        accessibilityLabel={`${item.title}. ${details}`}
        disabled={!openable}
        onPress={() => router.push(episodeHref(segments, item.id))}
      >
        <Artwork
          uri={item.artworkUrl ?? null}
          size={ART}
          className="rounded-lg"
        />
        <View className="flex-1 gap-1">
          <Text className="font-semibold" numberOfLines={2}>
            {item.title}
          </Text>
          {details ? (
            <Text className="text-muted-foreground text-sm" numberOfLines={1}>
              {details}
            </Text>
          ) : null}
          {progress === null ? null : (
            <View className="bg-foreground/10 h-0.5 overflow-hidden rounded-full">
              <View
                className="bg-primary h-0.5"
                style={{ width: `${Math.round(progress * 100)}%` }}
              />
            </View>
          )}
        </View>
      </Pressable>
    </Swipeable>
  )
}
