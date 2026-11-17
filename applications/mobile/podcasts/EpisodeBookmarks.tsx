// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { View } from "react-native"

import { Text } from "@/components/ui/text"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"

import { BookmarkRow, playBookmark } from "./BookmarkRow"
import { useEpisodeBookmarks } from "./useBookmarks"

/** The bookmarks of one episode, on its card. Nothing when it has none. */
export function EpisodeBookmarks({
  episode,
  show,
}: {
  episode: StoredEpisode
  show: Show | null
}) {
  const bookmarks = useEpisodeBookmarks(episode.id).data ?? []
  if (bookmarks.length === 0) return null
  return (
    <View className="w-full">
      <Text className="pb-1 text-lg font-bold" accessibilityRole="header">
        Bookmarks
      </Text>
      {bookmarks.map((bookmark) => (
        <BookmarkRow
          key={bookmark.id}
          bookmark={bookmark}
          onPlay={() => playBookmark(bookmark, episode, show)}
        />
      ))}
    </View>
  )
}
