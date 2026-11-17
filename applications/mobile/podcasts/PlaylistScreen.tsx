// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter } from "expo-router"
import { useMemo } from "react"
import { ActivityIndicator, FlatList, View } from "react-native"

import { Text } from "@/components/ui/text"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { rulePills } from "@/modules/podcasts/playlistRules"

import { EpisodeRow } from "./EpisodeRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SelectionBar, SelectionSpacer } from "./SelectionBar"
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
    <>
      {playlist.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : !current ? (
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            {playlist.error ?? "This playlist isn't there."}
          </Text>
        </BelowBar>
      ) : (
        <FlatList<StoredEpisode>
          className="bg-background flex-1"
          data={episodes.data ?? []}
          keyExtractor={(episode) => episode.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          extraData={selection.selected}
          ListHeaderComponent={
            <>
              {selection.on ? <SelectionSpacer /> : null}
              <View
                className="flex-row flex-wrap gap-2 py-2"
                accessible
                accessibilityLabel={rulePills(current.rules).join(", ")}
              >
                {rulePills(current.rules).map((pill) => (
                  <View
                    key={pill}
                    className="bg-foreground/10 rounded-full px-3 py-1"
                  >
                    <Text className="text-sm">{pill}</Text>
                  </View>
                ))}
              </View>
            </>
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
              <EpisodeRow
                artwork
                episode={item}
                show={show}
                selection={selection}
              />
            ) : null
          }}
        />
      )}
      <ScreenBar
        title={current?.title ?? "Playlist"}
        right={
          <>
            <Stack.Toolbar.Button
              icon="checklist"
              hidden={!current}
              accessibilityLabel="Select episodes"
              onPress={() => selection.begin()}
            />
            <Stack.Toolbar.Button
              icon="pencil"
              hidden={!current}
              accessibilityLabel="Edit the playlist"
              onPress={() =>
                current
                  ? router.push({
                      pathname:
                        "/podcasts/(tabs)/(playlists)/playlist-edit/[id]",
                      params: { id: current.id },
                    })
                  : undefined
              }
            />
          </>
        }
      />
      {selection.on ? (
        <SelectionBar
          selection={selection}
          episodes={episodes.data ?? []}
          shows={showById}
        />
      ) : null}
    </>
  )
}
