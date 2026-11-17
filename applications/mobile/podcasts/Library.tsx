// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import {
  Bookmark,
  CircleArrowDown,
  Clock,
  Flag,
  History,
  Layers,
  ListEnd,
  ListMusic,
  Radio,
} from "lucide-react-native"
import { useMemo } from "react"
import { Alert, FlatList, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { episodeCount } from "@/modules/podcasts/playlistLook"
import { type Playlist } from "@/modules/podcasts/playlists"
import {
  arrangeHref,
  bookmarksHref,
  downloadsHref,
  historyHref,
  latestHref,
  playlistEditHref,
  playlistHref,
  savedHref,
  showHref,
  showsHref,
  upNextHref,
} from "@/modules/podcasts/routes"

import { LibraryRow } from "./LibraryRow"
import { RecentCell, recentCellSize } from "./RecentlyUpdated"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { addAudioFiles } from "./addAudioFiles"
import { askNewPlaylist } from "./addToPlaylist"
import { useShows } from "./hooks"
import { useDownloadMap } from "./useDownloads"
import { useRecentShows, useStarred } from "./useEpisodeLists"
import { useItemCounts, usePlaylists, useSmartEpisodes } from "./usePlaylists"
import { useStatusBarStyle } from "./usePodcastsTheme"
import { useUpNext } from "./useUpNext"

/** One playlist as a row: a smart one is counted through its rules, a hand-filled one by its items. */
function PlaylistRow({
  playlist,
  onPress,
}: {
  playlist: Playlist
  onPress: () => void
}) {
  const manual = playlist.kind === "manual"
  const smartCount = useSmartEpisodes(manual ? null : playlist).data?.length
  const counts = useItemCounts().data
  const count = manual ? (counts?.get(playlist.id) ?? 0) : smartCount
  return (
    <LibraryRow
      icon={manual ? ListMusic : Radio}
      title={playlist.title}
      count={count}
      label={
        count === undefined
          ? playlist.title
          : `${playlist.title}, ${episodeCount(count)}`
      }
      onPress={onPress}
    />
  )
}

/**
 * The Library tab: the rooms (Shows, Saved, Downloaded, Latest Episodes, Up Next), one row per
 * playlist, History and Bookmarks, then "Recently Updated", the followed shows by their newest
 * episode in a two-column grid. The "..." menu has New playlist, Add audio files and Arrange.
 */
export function Library() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const segments = useSegments()
  const { width } = useWindowDimensions()
  const shows = useShows()
  const recent = useRecentShows()
  const saved = useStarred()
  const downloads = useDownloadMap()
  const queue = useUpNext()
  const playlists = usePlaylists()

  const showById = useMemo(
    () => new Map((shows.data ?? []).map((show) => [show.id, show])),
    [shows.data],
  )
  const grid = useMemo(
    () =>
      (recent.data ?? []).flatMap((entry) => {
        const show = showById.get(entry.showId)
        return show ? [{ show, entry }] : []
      }),
    [recent.data, showById],
  )
  const size = recentCellSize(width)
  const now = Date.now()

  function newSmart() {
    router.push(playlistEditHref(segments, "new"))
  }
  function newManual() {
    askNewPlaylist((id) => router.push(playlistHref(segments, id)))
  }
  function arrangeFirst() {
    if ((shows.data ?? []).length === 0) {
      Alert.alert("No shows yet", "Follow a show first, then arrange them.")
      return
    }
    router.push(arrangeHref(segments))
  }

  const header = (
    <View>
      <LibraryRow
        icon={Layers}
        title="Shows"
        onPress={() => router.push(showsHref(segments))}
      />
      <LibraryRow
        icon={Bookmark}
        title="Saved"
        count={saved.data?.length || null}
        onPress={() => router.push(savedHref(segments))}
      />
      <LibraryRow
        icon={CircleArrowDown}
        title="Downloaded"
        count={Object.keys(downloads).length || null}
        onPress={() => router.push(downloadsHref(segments))}
      />
      <LibraryRow
        icon={Clock}
        title="Latest Episodes"
        onPress={() => router.push(latestHref(segments))}
      />
      <LibraryRow
        icon={ListEnd}
        title="Up Next"
        count={queue.length || null}
        onPress={() => router.push(upNextHref(segments))}
      />
      {(playlists.data ?? []).map((playlist) => (
        <PlaylistRow
          key={playlist.id}
          playlist={playlist}
          onPress={() => router.push(playlistHref(segments, playlist.id))}
        />
      ))}
      <LibraryRow
        icon={History}
        title="History"
        onPress={() => router.push(historyHref(segments))}
      />
      <LibraryRow
        icon={Flag}
        title="Bookmarks"
        onPress={() => router.push(bookmarksHref(segments))}
      />
      {grid.length > 0 ? (
        <Text
          className="px-4 pt-8 pb-3 text-3xl font-bold"
          accessibilityRole="header"
        >
          Recently Updated
        </Text>
      ) : null}
    </View>
  )

  return (
    <>
      <FlatList
        className="bg-background flex-1"
        data={grid}
        numColumns={2}
        keyExtractor={(item) => item.show.id}
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ paddingBottom: 24 }}
        columnWrapperStyle={{
          gap: 12,
          paddingHorizontal: 16,
          marginBottom: 20,
        }}
        ListHeaderComponent={header}
        renderItem={({ item }) => (
          <RecentCell
            show={item.show}
            recent={item.entry}
            size={size}
            now={now}
            onPress={() => router.push(showHref(segments, item.show.id))}
          />
        )}
      />
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        account
        title="Library"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
        right={
          <Stack.Toolbar.Menu icon="ellipsis" accessibilityLabel="More">
            <Stack.Toolbar.Menu inline title="New playlist">
              <Stack.Toolbar.MenuAction
                icon="wand.and.stars"
                onPress={newSmart}
              >
                Smart playlist, from rules
              </Stack.Toolbar.MenuAction>
              <Stack.Toolbar.MenuAction
                icon="music.note.list"
                onPress={newManual}
              >
                Playlist I fill myself
              </Stack.Toolbar.MenuAction>
            </Stack.Toolbar.Menu>
            <Stack.Toolbar.MenuAction
              icon="doc.badge.plus"
              onPress={() => void addAudioFiles()}
            >
              Add audio files
            </Stack.Toolbar.MenuAction>
            <Stack.Toolbar.MenuAction
              icon="arrow.up.arrow.down"
              onPress={arrangeFirst}
            >
              Arrange shows
            </Stack.Toolbar.MenuAction>
          </Stack.Toolbar.Menu>
        }
      />
    </>
  )
}
