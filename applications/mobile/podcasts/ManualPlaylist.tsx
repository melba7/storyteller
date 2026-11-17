// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { Play } from "lucide-react-native"
import { useEffect, useRef, useState } from "react"
import { ActivityIndicator, Alert, Pressable, View } from "react-native"
import Swipeable, {
  type SwipeableMethods,
} from "react-native-gesture-handler/ReanimatedSwipeable"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  deletePlaylist,
  removeFromPlaylist,
  saveItemOrder,
  savePlaylist,
} from "@/modules/podcasts/dbPlaylists"
import { type PlaylistEntry } from "@/modules/podcasts/manualPlaylist"
import { readableError } from "@/modules/podcasts/nativeError"
import {
  entryDetails,
  entryLabel,
  episodeCount,
} from "@/modules/podcasts/playlistLook"
import { type Playlist } from "@/modules/podcasts/playlists"
import { previewHref, episodeHref } from "@/modules/podcasts/routes"
import { moveBetween } from "@/modules/podcasts/upNext"

import { Artwork } from "./Artwork"
import { DragList, type RowAction } from "./DragList"
import { PlayButton } from "./PlayButton"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { playAll } from "./playAll"
import { useEntries } from "./usePlaylists"

const ROW_HEIGHT = 76
const ACTIONS: RowAction[] = [{ name: "remove", label: "Remove" }]

function tell(title: string, cause: unknown) {
  Alert.alert(title, readableError(cause))
}

/**
 * A playlist you fill by hand: its episodes in order, drag a row by its handle to move it,
 * swipe left to remove it, and Play all. Rename and delete are in the menu.
 */
export function ManualPlaylist({ playlist }: { playlist: Playlist }) {
  const router = useRouter()
  const entries = useEntries(playlist.id)
  const list = entries.data ?? []
  // The order shown while it is dragged, until the saved order catches up.
  const [order, setOrder] = useState<string[] | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const byId = new Map(list.map((entry) => [entry.episode.id, entry]))
  const savedIds = list.map((entry) => entry.episode.id)
  const ids = order ?? savedIds

  // A drag still waiting to be saved is saved when the screen goes, not lost.
  const pending = useRef<string[] | null>(null)
  const playlistId = useRef(playlist.id)
  playlistId.current = playlist.id
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current)
      if (pending.current) {
        saveItemOrder(playlistId.current, pending.current).catch(
          (cause: unknown) =>
            console.warn("Couldn't save the playlist's order", cause),
        )
      }
    },
    [],
  )

  function reorder(next: string[]) {
    if (!moveBetween(ids, next)) return
    setOrder(next)
    pending.current = next
    if (timer.current) clearTimeout(timer.current)
    // Saved once the finger rests, not at every row it passes.
    timer.current = setTimeout(() => {
      pending.current = null
      saveItemOrder(playlist.id, next).then(
        () => setOrder(null),
        (cause: unknown) => {
          setOrder(null)
          tell("Couldn't move the episode", cause)
        },
      )
    }, 400)
  }

  function rename() {
    Alert.prompt(
      "Rename playlist",
      undefined,
      (name?: string) => {
        const title = name?.trim() ?? ""
        if (title === "") return
        savePlaylist({ ...playlist, title }).catch((cause: unknown) =>
          tell("Couldn't rename the playlist", cause),
        )
      },
      "plain-text",
      playlist.title,
    )
  }

  function confirmDelete() {
    Alert.alert(
      `Delete ${playlist.title}?`,
      "Only the playlist goes. Your episodes stay.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Delete",
          style: "destructive",
          onPress: () => {
            deletePlaylist(playlist.id).then(
              () => router.dismissTo("/podcasts/(tabs)/(playlists)"),
              (cause: unknown) => tell("Couldn't delete the playlist", cause),
            )
          },
        },
      ],
    )
  }

  return (
    <>
      {entries.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : list.length === 0 ? (
        <BelowBar>
          <View className="items-center gap-2 px-8 py-12">
            <Text className="text-center font-semibold">
              {entries.error ?? "Nothing in this playlist yet"}
            </Text>
            <Text className="text-muted-foreground text-center text-sm">
              Tap the three dots on any episode, or open it, and choose Add to
              playlist.
            </Text>
          </View>
        </BelowBar>
      ) : (
        <DragList
          header={
            <View className="flex-row items-center gap-2 py-2">
              <Text className="text-muted-foreground flex-1 text-sm">
                {episodeCount(list.length)}
              </Text>
              <Button
                className="rounded-full"
                accessibilityLabel="Play all"
                onPress={() => void playAll(list)}
              >
                <Icon as={Play} size={16} className="text-primary-foreground" />
                <Text>Play all</Text>
              </Button>
            </View>
          }
          ids={ids}
          rowHeight={ROW_HEIGHT}
          onChange={reorder}
          label={(id, index, count) => {
            const entry = byId.get(id)
            return entry ? entryLabel(entry, index, count) : ""
          }}
          actions={ACTIONS}
          onAction={(id, name) => {
            if (name === "remove") remove(playlist.id, id)
          }}
          renderContent={(id) => {
            const entry = byId.get(id)
            return entry ? (
              <EntryRow playlistId={playlist.id} entry={entry} />
            ) : null
          }}
        />
      )}
      <ScreenBar
        title={playlist.title}
        right={
          <Stack.Toolbar.Menu
            icon="ellipsis"
            accessibilityLabel="More for this playlist"
          >
            <Stack.Toolbar.MenuAction icon="pencil" onPress={rename}>
              Rename
            </Stack.Toolbar.MenuAction>
            <Stack.Toolbar.MenuAction
              icon="trash"
              destructive
              onPress={confirmDelete}
            >
              Delete playlist
            </Stack.Toolbar.MenuAction>
          </Stack.Toolbar.Menu>
        }
      />
    </>
  )
}

function remove(playlistId: string, episodeId: string) {
  removeFromPlaylist(playlistId, episodeId).catch((cause: unknown) =>
    tell("Couldn't remove the episode", cause),
  )
}

function EntryRow({
  playlistId,
  entry,
}: {
  playlistId: string
  entry: PlaylistEntry
}) {
  const router = useRouter()
  const segments = useSegments()
  const { episode, show } = entry
  const details = entryDetails(entry)

  function open() {
    if (entry.inLibrary) router.push(episodeHref(segments, episode.id))
    else if (show) {
      router.push(
        previewHref(segments, show.feedUrl, {
          guid: episode.guid,
          audioUrl: episode.audioUrl,
        }),
      )
    }
  }

  return (
    <Swipeable
      renderRightActions={(
        _progress,
        _translation,
        methods: SwipeableMethods,
      ) => (
        <Button
          variant="destructive"
          className="h-full w-20 rounded-none"
          accessibilityLabel={`Remove ${episode.title} from the playlist`}
          onPress={() => {
            methods.close()
            remove(playlistId, episode.id)
          }}
        >
          <Text className="text-xs">Remove</Text>
        </Button>
      )}
    >
      <View className="bg-background h-full flex-row items-center gap-3">
        <Pressable
          className="active:bg-secondary h-full flex-1 flex-row items-center gap-3"
          accessibilityRole="button"
          accessibilityLabel={`${episode.title}. ${details}`}
          disabled={!entry.inLibrary && !show}
          onPress={open}
        >
          <Artwork uri={episode.imageUrl ?? show?.imageUrl ?? null} size={52} />
          <View className="flex-1 gap-1">
            <Text className="font-semibold" numberOfLines={2}>
              {episode.title}
            </Text>
            {details ? (
              <Text className="text-muted-foreground text-sm" numberOfLines={1}>
                {details}
              </Text>
            ) : null}
          </View>
        </Pressable>
        <PlayButton episode={episode} show={show} size={36} />
      </View>
    </Swipeable>
  )
}
