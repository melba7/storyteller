// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { useMemo, useState } from "react"
import { Pressable, ScrollView, View, useWindowDimensions } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { Text } from "@/components/ui/text"
import { blendOver } from "@/modules/podcasts/artworkTint"
import { chapterArtwork } from "@/modules/podcasts/chapters"
import { lastTabSegments } from "@/modules/podcasts/lastTab"
import {
  MIN_ART_AREA,
  artworkPlan,
  sheetGutters,
  sideBySide,
  splitWidths,
} from "@/modules/podcasts/playerFrame"
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
  const windowSize = useWindowDimensions()
  const insets = useSafeAreaInsets()
  // A screen that opened the player may have asked for a page (the menu's "View Transcript").
  const [chosen, setChosen] = useState<PlayerPanel>(
    () => takePlayerPageRequest() ?? "art",
  )
  // Null until the room above the controls is measured: a measured 0 means no room at all.
  const [areaHeight, setAreaHeight] = useState<number | null>(null)
  const [sheet, setSheet] = useState({ width: 0, height: 0 })
  const sheetHeight = sheet.height
  // The sheet's own width: on iPad the modal sheet is narrower than the window.
  const width = sheet.width > 0 ? sheet.width : windowSize.width
  const { episode, show } = view
  const colors = useMemo(
    () => sheetColors(show?.artworkColor ?? null),
    [show?.artworkColor],
  )
  const chapters = useChapters(episode?.id ?? "")
  // The chapters panel goes away with the chapters (a new episode without any).
  const panel = chosen === "chapters" && chapters.length === 0 ? "art" : chosen
  // A short, wide sheet (phone landscape) puts the artwork or panel left of the controls.
  const split = sideBySide(sheet)
  const gutters = sheetGutters({ side: SIDE, insets, sideBySide: split })
  const columns = splitWidths(width)
  // The artwork is as wide as the sheet and square, and is cut off where the controls begin.
  // On a wide sheet with little height it is a centred square instead. Until the area is
  // measured it is as tall as it can be, so it doesn't jump.
  const plan = artworkPlan({
    sheetWidth: width,
    areaWidth: split ? columns.area : width,
    areaHeight,
    grabber: GRABBER,
    minArea: MIN_ART_AREA,
    sideBySide: split,
  })
  const artHeight = plan.kind === "edge" ? plan.height : 0
  // The sheet's gradient at the artwork's lower edge, where the fade ends.
  const fadeTo =
    sheetHeight > 0
      ? blendOver(
          colors.bottom,
          colors.top,
          Math.min(1, artHeight / sheetHeight),
        )
      : colors.top

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
        onLayout={(event) => {
          const { width: w, height: h } = event.nativeEvent.layout
          setSheet({ width: w, height: h })
        }}
        style={{
          backgroundColor: colors.top,
          backgroundImage: `linear-gradient(180deg, ${colors.top}, ${colors.bottom})`,
        }}
      >
        {panel === "art" && plan.kind !== "hidden" && episode ? (
          <PlayerArtwork
            uri={
              chapterArtwork(chapters, view.position) ??
              episode.imageUrl ??
              show?.imageUrl ??
              null
            }
            width={split ? columns.area : width}
            height={plan.kind === "contained" ? plan.height : artHeight}
            fadeTo={fadeTo}
            contained={plan.kind === "contained"}
            top={GRABBER}
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
            <View className={split ? "flex-1 flex-row" : "flex-1"}>
              <View
                className="flex-1"
                style={{
                  paddingLeft: panel === "art" ? 0 : gutters.areaLeft,
                  paddingRight: panel === "art" ? 0 : gutters.areaRight,
                  // `flex-1` gives a flex basis of 0, which wins over `width`: say it outright.
                  ...(split
                    ? {
                        width: columns.area,
                        flexBasis: columns.area,
                        flexGrow: 0,
                        flexShrink: 0,
                      }
                    : null),
                }}
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
                style={
                  split
                    ? {
                        width: columns.controls,
                        flexBasis: columns.controls,
                        flexGrow: 0,
                        flexShrink: 0,
                      }
                    : { flexGrow: 0, flexShrink: 1 }
                }
                bounces={false}
                showsVerticalScrollIndicator={false}
              >
                <PlayerNowPlaying
                  view={view}
                  chapters={chapters}
                  onPanel={setChosen}
                  onShow={goToShow}
                  left={gutters.controlsLeft}
                  right={gutters.controlsRight}
                />
                <View className="pt-1">
                  <PlayerToolbar panel={panel} onPanel={setChosen} />
                </View>
              </ScrollView>
            </View>
          </>
        )}
      </View>
    </SheetProvider>
  )
}
