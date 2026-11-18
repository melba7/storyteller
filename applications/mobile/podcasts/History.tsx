// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"
import { History as HistoryIcon } from "lucide-react-native"
import { useMemo } from "react"
import { ActivityIndicator, Alert, FlatList } from "react-native"

import { Text } from "@/components/ui/text"
import { clearHistory } from "@/modules/podcasts/dbEpisodes"
import { groupByDay } from "@/modules/podcasts/history"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"

import { EmptyState } from "./EmptyState"
import { EpisodeRow } from "./EpisodeRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SelectionBar, SelectionSpacer } from "./SelectionBar"
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
    <>
      {history.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : (
        <FlatList<Item>
          className="bg-background flex-1"
          data={items}
          keyExtractor={(item) => item.key}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          extraData={selection.selected}
          ListHeaderComponent={selection.on ? <SelectionSpacer /> : undefined}
          ListEmptyComponent={
            <EmptyState
              icon={HistoryIcon}
              title="No history yet"
              body={
                history.error ?? "Episodes you listen to show up here, by day."
              }
            />
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
                artwork
                episode={item.episode}
                show={show}
                selection={selection}
              />
            ) : null
          }}
        />
      )}
      <ScreenBar
        large
        title="History"
        right={
          <>
            <Stack.Toolbar.Button
              icon="checklist"
              hidden={episodes.length === 0}
              accessibilityLabel="Select episodes"
              onPress={() => selection.begin()}
            />
            <Stack.Toolbar.Button
              hidden={episodes.length === 0}
              accessibilityLabel="Clear the history"
              onPress={confirmClear}
            >
              Clear
            </Stack.Toolbar.Button>
          </>
        }
      />
      {selection.on ? (
        <SelectionBar
          selection={selection}
          episodes={episodes}
          shows={showById}
        />
      ) : null}
    </>
  )
}
