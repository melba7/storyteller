import { skipToken } from "@reduxjs/toolkit/query"
import deepmerge from "deepmerge"
import { useMemo } from "react"
import { View } from "react-native"
import { ScrollView } from "react-native-gesture-handler"

import { highlightTints, highlightUnderlines } from "@/colors"
import { useReaderFormSheetScrollPaddingBottom } from "@/components/toolbarItems/readerFormSheetLayout"
import { Stack } from "@/components/ui/Stack"
import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { useColorTheme } from "@/hooks/useColorTheme"
import { getHrefChapterTitle, positionToPageCount } from "@/links"
import { bookmarkPressed } from "@/store/actions"
import { useAppDispatch, useAppSelector } from "@/store/appState"
import {
  useGetBookHighlightsQuery,
  useGetBookPositionsQuery,
  useGetBookPreferencesQuery,
  useGetBookQuery,
  useGetGlobalPreferencesQuery,
} from "@/store/localApi"
import { getCurrentlyPlayingFormat } from "@/store/selectors/bookshelfSelectors"
import { type UUID } from "@/uuid"

interface Props {
  bookUuid?: UUID | undefined
  format?: "readaloud" | "ebook" | "audiobook" | undefined
  onClose?: () => void
}

export function Highlights({
  bookUuid: bookUuidProp,
  format: formatProp,
  onClose,
}: Props) {
  const selectedFormat = useAppSelector(getCurrentlyPlayingFormat)
  const bookUuid = bookUuidProp
  const format = formatProp ?? selectedFormat
  const paddingBottom = useReaderFormSheetScrollPaddingBottom()
  const dispatch = useAppDispatch()
  const { dark } = useColorTheme()
  const { data: highlights } = useGetBookHighlightsQuery(
    bookUuid ? { bookUuid } : skipToken,
  )
  const { data: book } = useGetBookQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )

  const toc =
    format === "readaloud"
      ? book?.readaloud?.epubManifest?.toc
      : format === "ebook"
        ? book?.ebook?.manifest?.toc
        : undefined

  const highlightTitles = useMemo(() => {
    return (
      highlights?.map((highlight) => {
        return (
          (toc ? getHrefChapterTitle(highlight.locator.href, toc) : null) ??
          highlight.locator.title ??
          "Untitled chapter"
        )
      }) ?? []
    )
  }, [highlights, toc])

  const { data: positions } = useGetBookPositionsQuery(
    bookUuid && (format === "readaloud" || format === "ebook")
      ? { bookUuid, format }
      : skipToken,
  )

  const highlightPages = useMemo(() => {
    if (!positions) return []

    return (
      highlights?.map((highlight) => {
        const chapterPositions = positions.filter(
          (position) => position.href === highlight.locator.href,
        )
        const highlightPosition =
          (chapterPositions.findIndex(
            (position) =>
              (position.locations?.progression ?? 0) >=
              (highlight.locator.locations?.progression ?? 0),
          ) ?? 0) + 1

        const highlightPage = positionToPageCount(highlightPosition)
        return highlightPage
      }) ?? []
    )
  }, [highlights, positions])

  const { data: bookPreferences } = useGetBookPreferencesQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )

  const { data: globalPreferences } = useGetGlobalPreferencesQuery()

  const preferences = useMemo(
    () =>
      bookPreferences
        ? globalPreferences && deepmerge(globalPreferences, bookPreferences)
        : globalPreferences,
    [globalPreferences, bookPreferences],
  )

  if (!highlights || !bookUuid) return null

  if (!highlights.length) {
    return (
      <Stack className="flex-1 items-center justify-center px-8 py-12">
        <Text className="text-muted-foreground text-center">
          No highlights yet! Try adding some by long pressing on the text to
          make a selection.
        </Text>
      </Stack>
    )
  }

  return (
    <ScrollView
      className="flex-1"
      contentContainerClassName="pt-1"
      contentContainerStyle={{ paddingBottom }}
    >
      {highlights.map((highlight, index) => (
        <View key={highlight.uuid}>
          <Button
            onPress={async () => {
              dispatch(
                bookmarkPressed({
                  bookUuid,
                  locator: highlight.locator,
                  timestamp: Date.now(),
                  currentLocator: book?.position?.locator,
                }),
              )
              onClose?.()
            }}
            variant="ghost"
            className="active:bg-secondary min-h-11 h-auto flex-col items-start rounded-none px-4 py-3 sm:h-auto"
          >
            <Text className="text-[17px] font-normal">
              {highlightTitles[index]}
            </Text>
            {highlight.locator.locations?.position && (
              <Text className="text-muted-foreground my-1 text-[15px]">
                Page {highlightPages[index]}
              </Text>
            )}
            {highlight.locator.text?.highlight && (
              <Text
                className="text-justify text-[15px] underline decoration-solid"
                style={{
                  fontFamily: preferences?.typography?.fontFamily,
                  textAlign: "left",
                  backgroundColor:
                    highlightTints[dark ? "dark" : "light"][highlight.color],
                  textDecorationColor:
                    highlightUnderlines[dark ? "dark" : "light"][
                      highlight.color
                    ],
                }}
              >
                {highlight.locator.text.highlight}
              </Text>
            )}
          </Button>
          <View className="bg-border ml-4 h-px" />
        </View>
      ))}
    </ScrollView>
  )
}
