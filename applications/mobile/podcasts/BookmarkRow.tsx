// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Bookmark as BookmarkIcon, Ellipsis } from "lucide-react-native"
import { Alert, Pressable, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import { type Bookmark, bookmarkLabel } from "@/modules/podcasts/bookmarks"
import { deleteBookmark, renameBookmark } from "@/modules/podcasts/dbBookmarks"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { formatTime } from "@/modules/podcasts/playbackRules"
import { player } from "@/modules/podcasts/playerInstance"

function tell(title: string, cause: unknown) {
  Alert.alert(title, readableError(cause))
}

/** Plays the episode from the bookmark's place. */
export function playBookmark(
  bookmark: Bookmark,
  episode: StoredEpisode,
  show: Show | null,
) {
  player
    .playFrom(episode, show, bookmark.positionSeconds)
    .catch((cause: unknown) => tell("Couldn't play from the bookmark", cause))
}

/**
 * One bookmark: its time and title (and a line about its episode when `context` is given).
 * Tap to play from there; the menu renames or deletes it.
 */
export function BookmarkRow({
  bookmark,
  context,
  onPlay,
}: {
  bookmark: Bookmark
  context?: string
  onPlay: () => void
}) {
  function rename() {
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
  return (
    <View className="border-border flex-row items-center gap-2 border-b py-2">
      <Pressable
        className="active:bg-secondary min-h-11 flex-1 flex-row items-center gap-3 rounded-md"
        accessibilityRole="button"
        accessibilityLabel={`Play from ${bookmarkLabel(bookmark)}`}
        onPress={onPlay}
      >
        <Icon as={BookmarkIcon} size={20} className="text-primary" />
        <View className="flex-1">
          <Text className="font-semibold" numberOfLines={2}>
            {bookmark.title}
          </Text>
          <Text className="text-muted-foreground text-sm" numberOfLines={1}>
            {[formatTime(bookmark.positionSeconds), context]
              .filter((part) => part !== undefined && part !== "")
              .join(" · ")}
          </Text>
        </View>
      </Pressable>
      <Menu
        actions={[
          { id: "rename", title: "Rename", onPress: rename },
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
        <Button
          variant="ghost"
          size="icon"
          accessibilityLabel={`More for ${bookmark.title}`}
        >
          <Icon as={Ellipsis} size={20} className="text-muted-foreground" />
        </Button>
      </Menu>
    </View>
  )
}
