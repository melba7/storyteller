// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useRouter } from "expo-router"
import { ChevronDown } from "lucide-react-native"
import { useState } from "react"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { playerGradient } from "@/modules/podcasts/artworkTint"
import { usePlayer } from "@/modules/podcasts/playerInstance"

import { ChapterList } from "./ChapterList"
import { PlayerNowPlaying } from "./PlayerNowPlaying"
import { NotesPage, PagePills, type PlayerPage, pagesFor } from "./PlayerPages"
import { TranscriptView } from "./TranscriptView"
import { useChapters } from "./useChapters"

/** The full-screen player: a gradient from the artwork, page pills, and the page chosen. */
export function PlayerScreen() {
  const router = useRouter()
  const view = usePlayer()
  const [chosen, setChosen] = useState<PlayerPage>("now")
  const { episode, show } = view
  const chapters = useChapters(episode?.id ?? "")
  const pages = pagesFor(chapters.length > 0)
  // The chapters page goes away with the chapters (a new episode without any).
  const page = pages.includes(chosen) ? chosen : "now"

  function close() {
    if (router.canGoBack()) router.back()
    else router.replace("/podcasts")
  }

  return (
    <View
      className="pt-safe flex-1"
      style={{ backgroundImage: playerGradient(show?.artworkColor ?? null) }}
    >
      <View className="px-safe-or-2 flex-row items-center">
        <Pressable
          className="size-11 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel="Close the player"
          onPress={close}
        >
          <Icon as={ChevronDown} size={28} className="text-white" />
        </Pressable>
        {episode ? (
          <PagePills pages={pages} page={page} onChange={setChosen} />
        ) : null}
      </View>

      {!episode ? (
        <Text className="px-8 py-12 text-center text-white/70">
          Nothing is playing. Pick an episode to start.
        </Text>
      ) : page === "chapters" ? (
        <ChapterList episodeId={episode.id} chapters={chapters} />
      ) : page === "transcript" ? (
        <TranscriptView key={episode.id} episode={episode} />
      ) : page === "notes" ? (
        <NotesPage notes={episode.notes} />
      ) : (
        <PlayerNowPlaying
          view={view}
          chapters={chapters}
          onOpenChapters={() => setChosen("chapters")}
        />
      )}
    </View>
  )
}
