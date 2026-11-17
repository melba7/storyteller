// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { useMemo, useState } from "react"
import { Pressable, ScrollView, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { blendOver } from "@/modules/podcasts/artworkTint"
import { chapterArtwork } from "@/modules/podcasts/chapters"
import { lastTabSegments } from "@/modules/podcasts/lastTab"
import { usePlayer } from "@/modules/podcasts/playerInstance"
import { takePlayerPageRequest } from "@/modules/podcasts/playerPageRequest"
import { sheetColors } from "@/modules/podcasts/playerSheet"
import { isPreviewId } from "@/modules/podcasts/preview"
import { previewHref, showHref } from "@/modules/podcasts/routes"

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

/** The space kept free left and right of the panels and the controls. */
const SIDE = 32
/** The height of the grabber's row, which the artwork reaches up under. */
const GRABBER = 24
/** Under this height (large text), the artwork area is too small for a picture, so it is left out. */
const MIN_ART_AREA = 140

/**
 * The player sheet: the artwork's colour as the whole background with a grabber at the top.
 * The artwork, or the transcript, the queue, the chapters, the notes or the bookmarks in its
 * place, then the title, scrubber, transport row, volume and the bottom row.
 */
export function PlayerScreen() {
  const router = useRouter()
  // The player is a modal, so its own segments name no tab: use the tab you were in.
  const segments = lastTabSegments()
  const view = usePlayer()
  const { width } = useWindowDimensions()
  // A screen that opened the player may have asked for a page (the menu's "View Transcript").
  const [chosen, setChosen] = useState<PlayerPanel>(
    () => takePlayerPageRequest() ?? "art",
  )
  const [areaHeight, setAreaHeight] = useState(0)
  const [sheetHeight, setSheetHeight] = useState(0)
  const { episode, show } = view
  const colors = useMemo(
    () => sheetColors(show?.artworkColor ?? null),
    [show?.artworkColor],
  )
  const chapters = useChapters(episode?.id ?? "")
  // The chapters panel goes away with the chapters (a new episode without any).
  const panel = chosen === "chapters" && chapters.length === 0 ? "art" : chosen
  // The artwork is as wide as the sheet and square, and is cut off where the controls begin.
  // Until the area is measured it is as tall as it can be, so it doesn't jump.
  const artHeight =
    areaHeight > 0 ? Math.min(width, areaHeight + GRABBER) : width
  // The sheet's gradient at the artwork's lower edge, where the fade ends.
  const fadeTo =
    sheetHeight > 0
      ? blendOver(
          colors.bottom,
          colors.top,
          Math.min(1, artHeight / sheetHeight),
        )
      : colors.top
  const showArt = areaHeight === 0 || areaHeight >= MIN_ART_AREA

  function close() {
    if (router.canGoBack()) router.back()
    else router.replace("/podcasts")
  }

  function goToShow() {
    if (!show || !episode) return
    close()
    router.push(
      isPreviewId(episode.id)
        ? previewHref(segments, show.feedUrl)
        : showHref(segments, show.id),
    )
  }

  // The player is a modal sheet, which already starts below the status bar, so its top needs
  // no safe-area padding. The plain top colour shows if a gradient can't be drawn.
  return (
    <SheetProvider value={colors}>
      <StatusBar style={colors.ink === "#ffffff" ? "light" : "dark"} />
      <View
        className="pb-safe-offset-2 flex-1"
        onLayout={(event) => setSheetHeight(event.nativeEvent.layout.height)}
        style={{
          backgroundColor: colors.top,
          backgroundImage: `linear-gradient(180deg, ${colors.top}, ${colors.bottom})`,
        }}
      >
        {panel === "art" && showArt && episode ? (
          <PlayerArtwork
            uri={
              chapterArtwork(chapters, view.position) ??
              episode.imageUrl ??
              show?.imageUrl ??
              null
            }
            width={width}
            height={artHeight}
            fadeTo={fadeTo}
          />
        ) : null}
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
              style={{ paddingHorizontal: panel === "art" ? 0 : SIDE }}
              onLayout={(event) =>
                setAreaHeight(event.nativeEvent.layout.height)
              }
            >
              {panel === "art" ? (
                <View className="flex-1" />
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
            {/* Everything under the artwork scrolls when large text makes it taller than the room left. */}
            <ScrollView
              style={{ flexGrow: 0, flexShrink: 1 }}
              bounces={false}
              showsVerticalScrollIndicator={false}
            >
              <PlayerNowPlaying
                view={view}
                chapters={chapters}
                onPanel={setChosen}
                onShow={goToShow}
              />
              <View className="pt-1">
                <PlayerToolbar panel={panel} onPanel={setChosen} />
              </View>
            </ScrollView>
          </>
        )}
      </View>
    </SheetProvider>
  )
}
