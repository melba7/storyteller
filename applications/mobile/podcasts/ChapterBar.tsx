// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Pressable } from "react-native"

import { Text } from "@/components/ui/text"
import { currentChapterIndex } from "@/modules/podcasts/chapters"
import type { PodcastChapter } from "@/modules/podcasts/index"

import { useSheet } from "./playerSheetContext"

/**
 * The chapter playing, centred between the scrubber's two times. A tap opens the chapter list;
 * the previous and next chapter are in the "..." menu. Nothing for an episode without chapters.
 */
export function ChapterTitle({
  chapters,
  position,
  onOpen,
}: {
  chapters: readonly PodcastChapter[]
  position: number
  onOpen: () => void
}) {
  const sheet = useSheet()
  if (chapters.length === 0) return null
  const index = currentChapterIndex(chapters, position)
  const title = index === null ? "Chapters" : (chapters[index]?.title ?? "")
  return (
    <Pressable
      className="min-h-11 flex-1 justify-center active:opacity-60"
      accessibilityRole="button"
      accessibilityLabel={`Chapter ${title}. Show all chapters`}
      onPress={onOpen}
    >
      <Text
        className="text-center text-sm font-semibold"
        style={{ color: sheet.tint }}
        numberOfLines={1}
      >
        {title}
      </Text>
    </Pressable>
  )
}
