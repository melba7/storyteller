// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ListChecks } from "lucide-react-native"
import { useMemo } from "react"
import { ActivityIndicator, Alert, FlatList, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { clearHistory } from "@/modules/podcasts/dbEpisodes"
import { groupByDay } from "@/modules/podcasts/history"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"

import { EpisodeRow } from "./EpisodeRow"
import { ScreenBar } from "./ScreenBar"
import { SelectionBar } from "./SelectionBar"
import { useShows } from "./hooks"
import { useHistory } from "./useEpisodeLists"
import { useSelection } from "./useSelection"

type Item =
  | { kind: "day"; key: string; title: string }
  | { kind: "episode"; key: string; episode: StoredEpisode }

function confirmClear() {
  Alert.alert(
    "Clear your listening history?",
    "The list is emptied. Where you are in each episode, and what is played, stays.",
    [
      { text: "Cancel", style: "cancel" },
      {
        text: "Clear",
        style: "destructive",
        onPress: () => {
          clearHistory().catch((cause: unknown) =>
            Alert.alert("Couldn't clear the history", readableError(cause)),
          )
        },
      },
    ],
  )
}

/** Listening history: the episodes you listened to, by day, the latest first. */
export function History() {
  const history = useHistory()
  const shows = useShows()
  const selection = useSelection()
  const showById = useMemo(
    () => new Map((shows.data ?? []).map((show) => [show.id, show])),
    [shows.data],
  )
  const episodes = history.data ?? []
  const items = useMemo<Item[]>(
    () =>
      groupByDay(episodes, Date.now()).flatMap((group) => [
        { kind: "day" as const, key: `day:${group.title}`, title: group.title },
        ...group.episodes.map((episode) => ({
          kind: "episode" as const,
          key: episode.id,
          episode,
        })),
      ]),
    // oxlint-disable-next-line react-hooks/exhaustive-deps
    [history.data],
  )
  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar
        title="Listening history"
        right={
          episodes.length > 0 ? (
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
                accessibilityLabel="Clear the history"
                onPress={confirmClear}
              >
                <Text className="text-primary">Clear</Text>
              </Button>
            </View>
          ) : undefined
        }
      />
      {selection.on ? (
        <SelectionBar
          selection={selection}
          episodes={episodes}
          shows={showById}
        />
      ) : null}
      {history.loading ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : (
        <FlatList<Item>
          data={items}
          keyExtractor={(item) => item.key}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          extraData={selection.selected}
          ListEmptyComponent={
            <Text className="text-muted-foreground px-4 py-12 text-center">
              {history.error ??
                "Nothing here yet. Episodes you listen to show up here."}
            </Text>
          }
          renderItem={({ item }) => {
            if (item.kind === "day") {
              return (
                <Text variant="h4" className="pt-4 pb-1">
                  {item.title}
                </Text>
              )
            }
            const show = showById.get(item.episode.showId)
            return show ? (
              <EpisodeRow
                episode={item.episode}
                show={show}
                selection={selection}
              />
            ) : null
          }}
        />
      )}
    </View>
  )
}
