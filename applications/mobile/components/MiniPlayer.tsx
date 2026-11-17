import { FastForward, Rewind } from "lucide-react-native"
import { useMemo, useRef } from "react"
import { TouchableOpacity, View } from "react-native"

import { GlassCapsule } from "@/apple-look/GlassCapsule"
import { type BookWithRelations } from "@/database/books"
import { cn } from "@/lib/utils"
import { getHrefChapterTitle, positionToPageCount } from "@/links"
import {
  bookDetailPressed,
  miniPlayerSliderChapterPositionChanged,
  nextFragmentPressed,
  playerPositionSeeked,
  playerTotalPositionSeeked,
  previousFragmentPressed,
} from "@/store/actions"
import { useAppDispatch, useAppSelector } from "@/store/appState"
import {
  useGetBookPositionsQuery,
  useGetBookPreferencesQuery,
} from "@/store/localApi"
import {
  formatTimeHuman,
  getBookDuration,
  getBookPosition,
  getCurrentTrackDuration,
  getCurrentTrackIndex,
  getPlaybackRate,
  getPosition,
  getTrackCount,
} from "@/store/selectors/bookshelfSelectors"

import { AudiobookCover } from "./AudiobookCover"
import { EbookCover } from "./EbookCover"
import { PlayPause } from "./PlayPause"
import { ProgressBar } from "./ProgressBar"
import { HideableView } from "./ui/HideableView"
import { Button } from "./ui/button"
import { Icon } from "./ui/icon"
import { Text } from "./ui/text"

type Props = {
  book: BookWithRelations
  format: "ebook" | "readaloud"
  hidden: boolean
  floatingToolbar: boolean
}

export function MiniPlayer({ book, format, hidden, floatingToolbar }: Props) {
  const locator = book.position?.locator
  const { data: bookPrefs } = useGetBookPreferencesQuery({ uuid: book.uuid })
  const position = useAppSelector(getPosition)
  const bookPosition = useAppSelector(getBookPosition)
  const bookDuration = useAppSelector(getBookDuration)
  const currentTrackIndex = useAppSelector(getCurrentTrackIndex)
  const trackCount = useAppSelector(getTrackCount)
  const trackDuration = useAppSelector(getCurrentTrackDuration)

  const rate = useAppSelector(getPlaybackRate)

  const trackPositionRef = useRef(position)
  trackPositionRef.current = position

  const dispatch = useAppDispatch()

  const manifest =
    format === "readaloud" ? book.readaloud?.epubManifest : book.ebook?.manifest
  const { data: positions } = useGetBookPositionsQuery({
    bookUuid: book.uuid,
    format,
  })

  const chapterTitle = useMemo(() => {
    if (!manifest?.toc) return null
    if (!locator?.href) return null

    return getHrefChapterTitle(locator.href, manifest.toc)
  }, [manifest?.toc, locator?.href])

  const chapterPositions = useMemo(() => {
    return (
      positions?.filter((position) => position.href === locator?.href) ?? []
    )
  }, [positions, locator?.href])

  const progress = useMemo(() => {
    if (bookPrefs?.detailView?.mode === "audio") {
      if (bookPrefs?.detailView?.scope === "book") {
        return bookPosition
      }
      return position
    }
    if (bookPrefs?.detailView?.scope === "book") {
      const position =
        locator?.locations?.position ??
        positions?.findIndex(
          (position) =>
            (position.locations?.totalProgression ?? 0) >=
            (locator?.locations?.totalProgression ?? 0),
        ) ??
        0

      return position === -1 ? (positions?.length ?? 1) : position + 1
    }
    const chapterPosition =
      chapterPositions.findIndex(
        (position) =>
          (position.locations?.progression ?? 0) >=
          (locator?.locations?.progression ?? 0),
      ) ?? 0

    return chapterPosition === -1
      ? (chapterPositions.length ?? 1)
      : chapterPosition + 1
  }, [
    positions,
    bookPrefs?.detailView?.mode,
    bookPrefs?.detailView?.scope,
    chapterPositions,
    locator?.locations?.position,
    locator?.locations?.progression,
    locator?.locations?.totalProgression,
    bookPosition,
    position,
  ])

  const { title, formattedProgress } = useMemo(() => {
    if (bookPrefs?.detailView?.mode === "audio") {
      if (bookPrefs.detailView.scope === "book") {
        return {
          title: book.title,
          formattedProgress: `${formatTimeHuman(bookDuration - progress, rate)} left`,
        }
      }
      return {
        title: `Track ${currentTrackIndex + 1} of ${trackCount}`,
        formattedProgress: `${formatTimeHuman(trackDuration - progress, rate)} left`,
      }
    }
    if (bookPrefs?.detailView?.scope === "book") {
      const position =
        locator?.locations?.position ??
        (positions?.findIndex(
          (position) =>
            (position.locations?.totalProgression ?? 0) >=
            (locator?.locations?.totalProgression ?? 0),
        ) ?? 0) + 1
      return {
        title: book.title,
        formattedProgress: `pg. ${positionToPageCount(position) || 1} / ${positionToPageCount(positions?.length ?? 0)}`,
      }
    }
    const chapterPosition = chapterPositions.findIndex(
      (position) =>
        (position.locations?.progression ?? 0) >=
        (locator?.locations?.progression ?? 0),
    )

    return {
      title: chapterTitle,
      formattedProgress: `pg. ${positionToPageCount(chapterPosition === -1 ? chapterPositions.length : chapterPosition + 1) || 1} / ${positionToPageCount(chapterPositions.length)}`,
    }
  }, [
    bookPrefs?.detailView?.mode,
    bookPrefs?.detailView?.scope,
    chapterPositions,
    chapterTitle,
    currentTrackIndex,
    trackCount,
    trackDuration,
    progress,
    rate,
    book.title,
    bookDuration,
    locator?.locations?.position,
    locator?.locations?.totalProgression,
    locator?.locations?.progression,
    positions,
  ])

  const progressStart = bookPrefs?.detailView?.mode === "audio" ? 0 : 1

  const progressEnd =
    bookPrefs?.detailView?.mode === "audio"
      ? bookPrefs?.detailView?.scope === "book"
        ? bookDuration
        : trackDuration
      : bookPrefs?.detailView?.scope === "book"
        ? positions?.length
        : chapterPositions.length

  return (
    bookPrefs && (
      <View>
        <HideableView
          hidden={hidden}
          className={cn(
            "ios:pb-safe-offset-2 android:pb-2 z-3 px-safe-or-3",
            {
              "ios:bottom-0 android:bottom-safe absolute right-0 left-0":
                floatingToolbar,
              "android:mb-safe-or-2": !floatingToolbar,
            },
          )}
        >
          {/* The scrubber sits above the capsule with a full-height touch area, because it moves
              through the chapter's pages in the reader. */}
          <View className="mb-1 px-4">
            <ProgressBar
              slim
              className="h-8"
              fillClassName="bg-primary"
              accessibilityLabel="Mini player progress"
              start={progressStart}
              stop={progressEnd ?? 0}
              progress={progress}
              onProgressChange={
                bookPrefs?.detailView?.scope === "book"
                  ? undefined
                  : (value) => {
                      if (bookPrefs?.detailView?.mode === "audio") {
                        if (bookPrefs?.detailView?.scope === "book") {
                          dispatch(
                            playerTotalPositionSeeked({ progress: value }),
                          )
                        } else {
                          dispatch(playerPositionSeeked({ progress: value }))
                        }
                      } else {
                        const nextLocator = chapterPositions[value - 1]
                        if (nextLocator === undefined) return
                        dispatch(
                          miniPlayerSliderChapterPositionChanged({
                            bookUuid: book.uuid,
                            locator: nextLocator,
                            timestamp: Date.now(),
                          }),
                        )
                      }
                    }
              }
            />
          </View>
          <GlassCapsule className="h-14">
            <View className="h-14 flex-row items-center gap-2 pr-2 pl-2">
              <TouchableOpacity
                accessibilityLabel={`Open details for ${title}`}
                accessibilityRole="button"
                className="w-10 p-0"
                onPress={() => {
                  dispatch(bookDetailPressed({ bookUuid: book.uuid, format }))
                }}
              >
                <View
                  className={cn(
                    "border-foreground/10 m-auto h-10 overflow-hidden border",
                    bookPrefs.detailView?.mode === "audio"
                      ? "w-10"
                      : "w-[26px]",
                  )}
                  style={{ borderRadius: 6 }}
                >
                  {bookPrefs.detailView?.mode === "audio" ? (
                    <AudiobookCover book={book} />
                  ) : (
                    <EbookCover book={book} />
                  )}
                </View>
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityLabel={`Open details for ${title}`}
                accessibilityRole="button"
                className="flex-1 flex-col items-stretch"
                onPress={() => {
                  dispatch(bookDetailPressed({ bookUuid: book.uuid, format }))
                }}
              >
                <Text
                  maxFontSizeMultiplier={1.25}
                  numberOfLines={1}
                  className="text-[15px] font-semibold"
                >
                  {title}
                </Text>
                <View className="grow flex-row justify-between gap-2">
                  <Text
                    maxFontSizeMultiplier={1.25}
                    numberOfLines={1}
                    className="text-muted-foreground shrink text-[13px]"
                  >
                    {formattedProgress}
                  </Text>
                  <Text
                    maxFontSizeMultiplier={1.25}
                    className="text-muted-foreground text-[13px]"
                  >
                    {Math.round(
                      (locator?.locations?.totalProgression ?? 0) * 100,
                    )}
                    %
                  </Text>
                </View>
              </TouchableOpacity>
              {format !== "ebook" && (
                <>
                  <Button
                    accessibilityLabel="Previous section"
                    variant="ghost"
                    size="icon"
                    className="rounded-full"
                    onPress={() => {
                      dispatch(previousFragmentPressed())
                    }}
                  >
                    <Icon as={Rewind} size={20} fill="currentColor" />
                  </Button>
                  <PlayPause automaticRewind={false} buttonSize="icon" />
                  <Button
                    accessibilityLabel="Next section"
                    variant="ghost"
                    size="icon"
                    className="rounded-full"
                    onPress={() => {
                      dispatch(nextFragmentPressed())
                    }}
                  >
                    <Icon as={FastForward} size={20} fill="currentColor" />
                  </Button>
                </>
              )}
            </View>
          </GlassCapsule>
        </HideableView>
      </View>
    )
  )
}
