// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useMemo } from "react"
import { ActivityIndicator, FlatList, View } from "react-native"

import { Text } from "@/components/ui/text"
import { type Bookmark } from "@/modules/podcasts/bookmarks"

import { BookmarkRow, playBookmark } from "./BookmarkRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { useEpisodesByIds, useShows } from "./hooks"
import { useAllBookmarks } from "./useBookmarks"

/** Profile's Bookmarks: every bookmark, the newest first. Tap one to play from there. */
export function Bookmarks() {
  const bookmarks = useAllBookmarks()
  const list = bookmarks.data ?? []
  const episodes = useEpisodesByIds([...new Set(list.map((b) => b.episodeId))])
  const shows = useShows()
  const episodeById = useMemo(
    () => new Map((episodes.data ?? []).map((e) => [e.id, e])),
    [episodes.data],
  )
  const showById = useMemo(
    () => new Map((shows.data ?? []).map((s) => [s.id, s])),
    [shows.data],
  )
  return (
    <View className="bg-background flex-1">
      <ScreenBar title="Bookmarks" />
      {bookmarks.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : (
        <FlatList<Bookmark>
          data={list}
          keyExtractor={(bookmark) => bookmark.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          ListEmptyComponent={
            <Text className="text-muted-foreground px-4 py-12 text-center">
              {bookmarks.error ??
                "No bookmarks yet. Tap the bookmark button in the player to mark a place."}
            </Text>
          }
          renderItem={({ item }) => {
            const episode = episodeById.get(item.episodeId)
            if (!episode) return null
            const show = showById.get(episode.showId) ?? null
            return (
              <BookmarkRow
                bookmark={item}
                context={[episode.title, show?.title ?? ""]
                  .filter((part) => part !== "")
                  .join(" · ")}
                onPlay={() => playBookmark(item, episode, show)}
              />
            )
          }}
        />
      )}
    </View>
  )
}
