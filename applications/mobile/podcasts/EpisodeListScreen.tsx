// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"
import type { LucideIcon } from "lucide-react-native"
import { useMemo } from "react"
import { ActivityIndicator, FlatList } from "react-native"

import { type StoredEpisode } from "@/modules/podcasts/library"

import { EmptyState } from "./EmptyState"
import { EpisodeRow } from "./EpisodeRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SelectionBar, SelectionSpacer } from "./SelectionBar"
import { type Query, useShows } from "./hooks"
import { useSelection } from "./useSelection"

/**
 * A plain list of episodes with the multi-select bar (Saved and Latest Episodes): each one an
 * `EpisodeRow` with its artwork. Episodes whose show is no longer followed are left out.
 */
export function EpisodeListScreen({
  title,
  episodes,
  icon,
  emptyTitle,
  emptyBody,
}: {
  title: string
  episodes: Query<StoredEpisode[]>
  icon: LucideIcon
  emptyTitle: string
  emptyBody: string
}) {
  const shows = useShows()
  const selection = useSelection()
  const showById = useMemo(
    () => new Map((shows.data ?? []).map((show) => [show.id, show])),
    [shows.data],
  )
  const list = episodes.data ?? []
  return (
    <>
      {episodes.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : (
        <FlatList<StoredEpisode>
          className="bg-background flex-1"
          data={list}
          keyExtractor={(episode) => episode.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          extraData={selection.selected}
          ListHeaderComponent={selection.on ? <SelectionSpacer /> : undefined}
          ListEmptyComponent={
            <EmptyState
              icon={icon}
              title={emptyTitle}
              body={episodes.error ?? emptyBody}
            />
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
        large
        title={title}
        right={
          <Stack.Toolbar.Button
            icon="checklist"
            hidden={list.length === 0}
            accessibilityLabel="Select episodes"
            onPress={() => selection.begin()}
          />
        }
      />
      {selection.on ? (
        <SelectionBar selection={selection} episodes={list} shows={showById} />
      ) : null}
    </>
  )
}
