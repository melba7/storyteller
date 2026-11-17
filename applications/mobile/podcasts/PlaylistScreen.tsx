// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { ListChecks, Pencil } from "lucide-react-native"
import { useMemo } from "react"
import { ActivityIndicator, FlatList, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { describeRules } from "@/modules/podcasts/playlistRules"

import { EpisodeRow } from "./EpisodeRow"
import { ScreenBar } from "./ScreenBar"
import { SelectionBar } from "./SelectionBar"
import { useShows } from "./hooks"
import { usePlaylist, useSmartEpisodes } from "./usePlaylists"
import { useSelection } from "./useSelection"

/** One smart playlist: what its rules ask for, and the episodes they take, in its order. */
export function PlaylistScreen({ id }: { id: string }) {
  const router = useRouter()
  const playlist = usePlaylist(id)
  const episodes = useSmartEpisodes(playlist.data)
  const shows = useShows()
  const selection = useSelection()
  const showById = useMemo(
    () => new Map((shows.data ?? []).map((show) => [show.id, show])),
    [shows.data],
  )
  const current = playlist.data
  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar
        title={current?.title ?? "Playlist"}
        right={
          current ? (
            <View className="flex-row items-center">
              <Button
                variant="ghost"
                size="icon"
                accessibilityLabel="Select episodes"
                onPress={() => selection.begin()}
              >
                <Icon as={ListChecks} size={20} className="text-primary" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                accessibilityLabel="Edit the playlist"
                onPress={() =>
                  router.push({
                    pathname: "/podcasts/(tabs)/(playlists)/playlist-edit/[id]",
                    params: { id: current.id },
                  })
                }
              >
                <Icon as={Pencil} size={20} className="text-primary" />
              </Button>
            </View>
          ) : undefined
        }
      />
      {selection.on ? (
        <SelectionBar
          selection={selection}
          episodes={episodes.data ?? []}
          shows={showById}
        />
      ) : null}
      {playlist.loading ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : !current ? (
        <Text className="text-muted-foreground px-8 py-12 text-center">
          {playlist.error ?? "This playlist isn't there."}
        </Text>
      ) : (
        <FlatList<StoredEpisode>
          data={episodes.data ?? []}
          keyExtractor={(episode) => episode.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          extraData={selection.selected}
          ListHeaderComponent={
            <Text className="text-muted-foreground py-2 text-sm">
              {describeRules(current.rules)}
            </Text>
          }
          ListEmptyComponent={
            episodes.loading ? undefined : (
              <Text className="text-muted-foreground py-6 text-center text-sm">
                {episodes.error ?? "No episodes match this playlist's rules."}
              </Text>
            )
          }
          renderItem={({ item }) => {
            const show = showById.get(item.showId)
            return show ? (
              <EpisodeRow episode={item} show={show} selection={selection} />
            ) : null
          }}
        />
      )}
    </View>
  )
}
