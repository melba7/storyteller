// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { ScrollView, Switch, Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { currentChapterIndex } from "@/modules/podcasts/chapters"
import type { PodcastChapter } from "@/modules/podcasts/index"
import { formatTime } from "@/modules/podcasts/playbackRules"
import { player, usePlayer } from "@/modules/podcasts/playerInstance"

import { Artwork } from "./Artwork"
import { pick } from "./haptics"
import { useSheet } from "./playerSheetContext"
import { chapterActions } from "./useChapters"

/**
 * The chapters of the episode under the player's top bar: the one playing is highlighted, a
 * tap plays from the start of a chapter, and each has a switch to skip it. A skipped chapter
 * is jumped over as ads are, but one you tap or seek into plays.
 */
export function ChapterList({
  episodeId,
  chapters,
}: {
  episodeId: string
  chapters: readonly PodcastChapter[]
}) {
  const view = usePlayer()
  const playing = currentChapterIndex(chapters, view.position)
  const sheet = useSheet()

  function play(chapter: PodcastChapter) {
    pick()
    void player.seekTo(chapter.start)
    void player.play()
  }

  return (
    <ScrollView contentContainerClassName="px-1 pb-3 gap-1">
      {chapters.map((chapter, index) => (
        <View
          key={chapter.start}
          className="flex-row items-center gap-3 rounded-xl px-2 py-2"
          style={
            index === playing ? { backgroundColor: sheet.rest } : undefined
          }
        >
          <Pressable
            className="min-h-12 flex-1 flex-row items-center gap-3 active:opacity-70"
            accessibilityRole="button"
            accessibilityLabel={`Play chapter ${chapter.title} from ${formatTime(chapter.start)}`}
            accessibilityState={{ selected: index === playing }}
            onPress={() => play(chapter)}
          >
            {chapter.imageUrl ? (
              <Artwork
                uri={chapter.imageUrl}
                size={44}
                className="rounded-lg"
              />
            ) : null}
            <View className="flex-1">
              <Text
                className={`text-base ${
                  index === playing ? "font-bold" : "font-medium"
                } ${chapter.skipped ? "opacity-50" : ""}`}
                style={{ color: sheet.ink }}
                numberOfLines={2}
              >
                {chapter.title}
              </Text>
              <Text className="text-sm" style={{ color: sheet.muted }}>
                {formatTime(chapter.start)}
              </Text>
            </View>
          </Pressable>
          <Switch
            value={chapter.skipped}
            accessibilityLabel={`Skip the chapter ${chapter.title}`}
            onValueChange={(skipped) =>
              chapterActions.setSkipped(episodeId, chapter.start, skipped)
            }
          />
        </View>
      ))}
    </ScrollView>
  )
}
