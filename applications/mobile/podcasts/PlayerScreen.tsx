// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { useMemo, useState } from "react"
import { Pressable, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { chapterArtwork } from "@/modules/podcasts/chapters"
import { usePlayer } from "@/modules/podcasts/playerInstance"
import { sheetColors } from "@/modules/podcasts/playerSheet"
import { showHref } from "@/modules/podcasts/routes"

import { ChapterList } from "./ChapterList"
import { PlayerArtwork } from "./PlayerArtwork"
import { PlayerNowPlaying } from "./PlayerNowPlaying"
import {
  BookmarksPage,
  NotesPage,
  PanelTitle,
  type PlayerPanel,
} from "./PlayerPages"
import { PlayerQueue } from "./PlayerQueue"
import { PlayerToolbar } from "./PlayerToolbar"
import { TranscriptView } from "./TranscriptView"
import { SheetProvider } from "./playerSheetContext"
import { useChapters } from "./useChapters"

/** The space kept free left and right of the artwork and the controls. */
const SIDE = 32

/**
 * The player sheet: the artwork's colour as the whole background with a grabber at the top.
 * The artwork, or the transcript, the queue, the chapters, the notes or the bookmarks in its
 * place, then the title, scrubber, transport row, volume and the bottom row.
 */
export function PlayerScreen() {
  const router = useRouter()
  const segments = useSegments()
  const view = usePlayer()
  const { width } = useWindowDimensions()
  const [chosen, setChosen] = useState<PlayerPanel>("art")
  const [areaHeight, setAreaHeight] = useState(0)
  const { episode, show } = view
  const colors = useMemo(
    () => sheetColors(show?.artworkColor ?? null),
    [show?.artworkColor],
  )
  const chapters = useChapters(episode?.id ?? "")
  // The chapters panel goes away with the chapters (a new episode without any).
  const panel = chosen === "chapters" && chapters.length === 0 ? "art" : chosen
  const size = Math.max(120, Math.min(width - SIDE * 2, areaHeight - 8))

  function close() {
    if (router.canGoBack()) router.back()
    else router.replace("/podcasts")
  }

  function goToShow() {
    if (!show) return
    close()
    router.push(showHref(segments, show.id))
  }

  // The player is a modal sheet, which already starts below the status bar, so its top needs
  // no safe-area padding. The plain top colour shows if a gradient can't be drawn.
  return (
    <SheetProvider value={colors}>
      <View
        className="pb-safe-offset-2 flex-1"
        style={{
          backgroundColor: colors.top,
          backgroundImage: `linear-gradient(180deg, ${colors.top}, ${colors.bottom})`,
        }}
      >
        <Pressable
          className="h-6 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel="Close the player"
          onPress={close}
        >
          <View
            className="h-1.5 w-10 rounded-full"
            style={{ backgroundColor: colors.rest }}
          />
        </Pressable>

        {!episode ? (
          <Text
            className="px-8 py-12 text-center"
            style={{ color: colors.tint }}
          >
            Nothing is playing. Pick an episode to start.
          </Text>
        ) : (
          <>
            <View
              className="flex-1"
              style={{ paddingHorizontal: SIDE }}
              onLayout={(event) =>
                setAreaHeight(event.nativeEvent.layout.height)
              }
            >
              {panel === "art" ? (
                <View className="flex-1 items-center justify-center">
                  <PlayerArtwork
                    uri={
                      chapterArtwork(chapters, view.position) ??
                      episode.imageUrl ??
                      show?.imageUrl ??
                      null
                    }
                    size={size}
                    playing={view.isPlaying}
                  />
                </View>
              ) : panel === "transcript" ? (
                <TranscriptView key={episode.id} episode={episode} />
              ) : panel === "queue" ? (
                <PlayerQueue />
              ) : panel === "chapters" ? (
                <View className="flex-1">
                  <PanelTitle
                    title="Chapters"
                    onDone={() => setChosen("art")}
                  />
                  <ChapterList episodeId={episode.id} chapters={chapters} />
                </View>
              ) : panel === "bookmarks" ? (
                <BookmarksPage
                  episode={episode}
                  show={show}
                  onDone={() => setChosen("art")}
                />
              ) : (
                <NotesPage
                  notes={episode.notes}
                  onDone={() => setChosen("art")}
                />
              )}
            </View>
            <PlayerNowPlaying
              view={view}
              chapters={chapters}
              onPanel={setChosen}
              onShow={goToShow}
            />
            <View className="pt-1">
              <PlayerToolbar panel={panel} onPanel={setChosen} />
            </View>
          </>
        )}
      </View>
    </SheetProvider>
  )
}
