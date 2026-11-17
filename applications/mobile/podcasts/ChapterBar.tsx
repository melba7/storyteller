// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { SkipBack, SkipForward } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { currentChapterIndex } from "@/modules/podcasts/chapters"
import type { PodcastChapter } from "@/modules/podcasts/index"

import { pick } from "./haptics"
import { chapterActions } from "./useChapters"

/** Under the seek bar: the chapter playing, with buttons for the previous and next chapter. */
export function ChapterBar({
  chapters,
  position,
  onOpen,
}: {
  chapters: readonly PodcastChapter[]
  position: number
  onOpen: () => void
}) {
  if (chapters.length === 0) return null
  const index = currentChapterIndex(chapters, position)
  const title = index === null ? "Chapters" : (chapters[index]?.title ?? "")
  return (
    <View className="w-full flex-row items-center gap-2">
      <Pressable
        className="size-11 items-center justify-center active:opacity-60"
        accessibilityRole="button"
        accessibilityLabel="Previous chapter"
        onPress={() => {
          pick()
          chapterActions.previous()
        }}
      >
        <Icon as={SkipBack} size={24} className="text-white" />
      </Pressable>
      <Pressable
        className="min-h-11 flex-1 justify-center active:opacity-70"
        accessibilityRole="button"
        accessibilityLabel={`Chapter ${title}. Show all chapters`}
        onPress={onOpen}
      >
        <Text
          className="text-center text-sm font-semibold text-white"
          numberOfLines={1}
        >
          {title}
        </Text>
      </Pressable>
      <Pressable
        className="size-11 items-center justify-center active:opacity-60"
        accessibilityRole="button"
        accessibilityLabel="Next chapter"
        onPress={() => {
          pick()
          chapterActions.next()
        }}
      >
        <Icon as={SkipForward} size={24} className="text-white" />
      </Pressable>
    </View>
  )
}
