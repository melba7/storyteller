// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { ChevronRight, ListMusic, Sparkles } from "lucide-react-native"
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  View,
} from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { episodeCount, playlistLine } from "@/modules/podcasts/playlistLook"
import { describeRules } from "@/modules/podcasts/playlistRules"
import { type Playlist } from "@/modules/podcasts/playlists"

import { EmptyState } from "./EmptyState"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { askNewPlaylist } from "./addToPlaylist"
import { useItemCounts, usePlaylists, useSmartEpisodes } from "./usePlaylists"
import { useStatusBarStyle } from "./usePodcastsTheme"

/** The Playlists tab: the smart playlists, each with how many episodes it holds now. */
export function Playlists() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const playlists = usePlaylists()

  function newSmart() {
    router.push({
      pathname: "/podcasts/(tabs)/(playlists)/playlist-edit/[id]",
      params: { id: "new" },
    })
  }
  function newManual() {
    askNewPlaylist((id) =>
      router.push({
        pathname: "/podcasts/(tabs)/(playlists)/playlist/[id]",
        params: { id },
      }),
    )
  }
  // The empty screen's button has no menu to open, so it asks the same choice in an alert.
  function chooseNew() {
    Alert.alert("New playlist", undefined, [
      { text: "Smart playlist, from rules", onPress: newSmart },
      { text: "Playlist I fill myself", onPress: newManual },
      { text: "Cancel", style: "cancel" },
    ])
  }

  return (
    <>
      {playlists.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : (
        <FlatList<Playlist>
          className="bg-background flex-1"
          data={playlists.data ?? []}
          keyExtractor={(playlist) => playlist.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          ListEmptyComponent={
            <EmptyState
              icon={ListMusic}
              title="No playlists yet"
              body={
                playlists.error ??
                "Make one from rules you choose, or fill one yourself."
              }
              action={{ label: "New playlist", onPress: chooseNew }}
            />
          }
          renderItem={({ item }) => <PlaylistRow playlist={item} />}
        />
      )}
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Playlists"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
        right={
          <Stack.Toolbar.Menu icon="plus" accessibilityLabel="New playlist">
            <Stack.Toolbar.MenuAction icon="wand.and.stars" onPress={newSmart}>
              Smart playlist, from rules
            </Stack.Toolbar.MenuAction>
            <Stack.Toolbar.MenuAction
              icon="music.note.list"
              onPress={newManual}
            >
              Playlist I fill myself
            </Stack.Toolbar.MenuAction>
          </Stack.Toolbar.Menu>
        }
      />
    </>
  )
}

function PlaylistRow({ playlist }: { playlist: Playlist }) {
  const router = useRouter()
  const manual = playlist.kind === "manual"
  // A smart playlist is read through its rules, a hand-filled one counted.
  const smartCount = useSmartEpisodes(manual ? null : playlist).data?.length
  const counts = useItemCounts().data
  const count = manual ? (counts?.get(playlist.id) ?? 0) : smartCount
  const summary = manual ? "Filled by you" : describeRules(playlist.rules)
  const line = playlistLine(count, summary)
  const label = count === undefined ? "" : episodeCount(count)
  return (
    <Pressable
      className="border-border active:bg-secondary flex-row items-center gap-3 border-b py-4"
      accessibilityRole="button"
      accessibilityLabel={`${playlist.title}, ${label}. ${summary}`}
      onPress={() =>
        router.push({
          pathname: "/podcasts/(tabs)/(playlists)/playlist/[id]",
          params: { id: playlist.id },
        })
      }
    >
      <View className="bg-primary/15 size-11 items-center justify-center rounded-xl">
        <Icon
          as={manual ? ListMusic : Sparkles}
          size={22}
          className="text-primary"
        />
      </View>
      <View className="flex-1 gap-1">
        <Text className="font-semibold">{playlist.title}</Text>
        <Text className="text-muted-foreground text-sm" numberOfLines={2}>
          {line}
        </Text>
      </View>
      <Icon as={ChevronRight} size={20} className="text-muted-foreground" />
    </Pressable>
  )
}
