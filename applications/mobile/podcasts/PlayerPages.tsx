// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Bookmark as BookmarkIcon, Ellipsis } from "lucide-react-native"
import type { ReactNode } from "react"
import { Alert, Pressable, ScrollView, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import { type Bookmark, bookmarkLabel } from "@/modules/podcasts/bookmarks"
import { deleteBookmark, renameBookmark } from "@/modules/podcasts/dbBookmarks"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { formatTime } from "@/modules/podcasts/playbackRules"

import { playBookmark } from "./BookmarkRow"
import { useSheet } from "./playerSheetContext"
import { useEpisodeBookmarks } from "./useBookmarks"

/** What takes the artwork's place in the player. */
export type PlayerPanel =
  | "art"
  | "transcript"
  | "queue"
  | "chapters"
  | "notes"
  | "bookmarks"

/** A panel's bold title, with an optional button at its right. */
export function PanelTitle({
  title,
  right,
  onDone,
}: {
  title: string
  right?: ReactNode
  /** Adds a "Done" button that brings the artwork back. */
  onDone?: () => void
}) {
  const sheet = useSheet()
  return (
    <View className="flex-row items-center justify-between px-1 pb-2">
      <Text
        className="text-xl font-bold"
        style={{ color: sheet.ink }}
        accessibilityRole="header"
      >
        {title}
      </Text>
      {right}
      {onDone ? (
        <Pressable
          className="min-h-11 justify-center px-2 active:opacity-60"
          accessibilityRole="button"
          accessibilityLabel={`Close ${title} and show the artwork`}
          onPress={onDone}
        >
          <Text className="font-semibold" style={{ color: sheet.tint }}>
            Done
          </Text>
        </Pressable>
      ) : null}
    </View>
  )
}

/** The episode's show notes, in place of the artwork. */
export function NotesPage({
  notes,
  onDone,
}: {
  notes: string
  onDone: () => void
}) {
  const sheet = useSheet()
  return (
    <View className="flex-1">
      <PanelTitle title="Notes" onDone={onDone} />
      <ScrollView
        contentContainerClassName="px-1 pb-3"
        showsVerticalScrollIndicator={false}
      >
        <Text
          selectable
          className="text-base leading-6"
          style={{ color: sheet.ink }}
        >
          {notes === "" ? "No notes for this episode." : notes}
        </Text>
      </ScrollView>
    </View>
  )
}

function tell(title: string, cause: unknown) {
  Alert.alert(title, readableError(cause))
}

function rename(bookmark: Bookmark) {
  Alert.prompt(
    "Rename bookmark",
    undefined,
    (title?: string) => {
      renameBookmark(bookmark, title ?? "").catch((cause: unknown) =>
        tell("Couldn't rename the bookmark", cause),
      )
    },
    "plain-text",
    bookmark.title,
  )
}

/** The episode's bookmarks, in place of the artwork: tap to play from one, "..." to rename or delete. */
export function BookmarksPage({
  episode,
  show,
  onDone,
}: {
  episode: StoredEpisode
  show: Show | null
  onDone: () => void
}) {
  const sheet = useSheet()
  const bookmarks = useEpisodeBookmarks(episode.id).data ?? []
  return (
    <View className="flex-1">
      <PanelTitle title="Bookmarks" onDone={onDone} />
      <ScrollView
        contentContainerClassName="px-1 pb-3"
        showsVerticalScrollIndicator={false}
      >
        {bookmarks.length === 0 ? (
          <Text className="text-base" style={{ color: sheet.tint }}>
            {
              'No bookmarks yet. Choose Add Bookmark in the "..." menu to keep a place.'
            }
          </Text>
        ) : null}
        {bookmarks.map((bookmark) => (
          <View key={bookmark.id} className="flex-row items-center gap-2 py-1">
            <Pressable
              className="min-h-11 flex-1 flex-row items-center gap-3 active:opacity-60"
              accessibilityRole="button"
              accessibilityLabel={`Play from ${bookmarkLabel(bookmark)}`}
              onPress={() => playBookmark(bookmark, episode, show)}
            >
              <Icon as={BookmarkIcon} size={20} color={sheet.tint} />
              <View className="flex-1">
                <Text
                  className="font-semibold"
                  style={{ color: sheet.ink }}
                  numberOfLines={2}
                >
                  {bookmark.title}
                </Text>
                <Text className="text-sm" style={{ color: sheet.muted }}>
                  {formatTime(bookmark.positionSeconds)}
                </Text>
              </View>
            </Pressable>
            <Menu
              actions={[
                {
                  id: "rename",
                  title: "Rename",
                  onPress: () => rename(bookmark),
                },
                {
                  id: "delete",
                  title: "Delete",
                  attributes: { destructive: true },
                  onPress: () => {
                    deleteBookmark(bookmark.id).catch((cause: unknown) =>
                      tell("Couldn't delete the bookmark", cause),
                    )
                  },
                },
              ]}
            >
              <View
                className="size-11 items-center justify-center"
                accessibilityRole="button"
                accessibilityLabel={`More for ${bookmark.title}`}
              >
                <Icon as={Ellipsis} size={20} color={sheet.tint} />
              </View>
            </Menu>
          </View>
        ))}
      </ScrollView>
    </View>
  )
}
