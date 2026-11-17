import { skipToken } from "@reduxjs/toolkit/query"
import { Trash2 } from "lucide-react-native"
import { useMemo } from "react"
import { View } from "react-native"
import { ScrollView } from "react-native-gesture-handler"
import Swipeable from "react-native-gesture-handler/ReanimatedSwipeable"

import { useReaderFormSheetScrollPaddingBottom } from "@/components/toolbarItems/readerFormSheetLayout"
import { Stack } from "@/components/ui/Stack"
import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { getHrefChapterTitle, positionToPageCount } from "@/links"
import { getAudiobookLocatorDetails } from "@/modules/readium"
import { bookmarkPressed } from "@/store/actions"
import { useAppDispatch, useAppSelector } from "@/store/appState"
import {
  useDeleteBookmarksMutation,
  useGetBookBookmarksQuery,
  useGetBookPositionsQuery,
  useGetBookQuery,
} from "@/store/localApi"
import {
  formatTime,
  getCurrentlyPlayingFormat,
} from "@/store/selectors/bookshelfSelectors"
import { type UUID } from "@/uuid"

interface Props {
  bookUuid?: UUID | undefined
  format?: "readaloud" | "ebook" | "audiobook" | undefined
  onClose?: () => void
}

export function Bookmarks({
  bookUuid: bookUuidProp,
  format: formatProp,
  onClose,
}: Props) {
  const selectedFormat = useAppSelector(getCurrentlyPlayingFormat)
  const bookUuid = bookUuidProp
  const format = formatProp ?? selectedFormat
  const paddingBottom = useReaderFormSheetScrollPaddingBottom()
  const dispatch = useAppDispatch()
  const { data: bookmarks } = useGetBookBookmarksQuery(
    bookUuid ? { bookUuid } : skipToken,
  )
  const { data: book } = useGetBookQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )
  const [deleteBookmarks] = useDeleteBookmarksMutation()

  const sortedBookmarks = useMemo(() => {
    return [...(bookmarks ?? [])].sort((a, b) =>
      b.createdAt.localeCompare(a.createdAt),
    )
  }, [bookmarks])

  const toc =
    format === "readaloud"
      ? book?.readaloud?.epubManifest?.toc
      : format === "ebook"
        ? book?.ebook?.manifest?.toc
        : undefined

  const bookmarkTitles = useMemo(() => {
    return sortedBookmarks.map((bookmark) => {
      return (
        (toc ? getHrefChapterTitle(bookmark.locator.href, toc) : null) ??
        bookmark.locator.title ??
        "Untitled chapter"
      )
    })
  }, [sortedBookmarks, toc])

  const { data: positions } = useGetBookPositionsQuery(
    bookUuid && (format === "readaloud" || format === "ebook")
      ? { bookUuid, format }
      : skipToken,
  )

  const bookmarkPages = useMemo(() => {
    if (!positions) return []

    return sortedBookmarks.map((bookmark) => {
      const chapterPositions = positions.filter(
        (position) => position.href === bookmark.locator.href,
      )
      const bookmarkPosition =
        (chapterPositions.findIndex(
          (position) =>
            (position.locations?.progression ?? 0) >=
            (bookmark.locator.locations?.progression ?? 0),
        ) ?? 0) + 1

      const bookmarkPage = positionToPageCount(bookmarkPosition)
      return bookmarkPage
    })
  }, [positions, sortedBookmarks])

  const audiobookBookmarkDetails = useMemo(() => {
    if (format !== "audiobook") return []

    return sortedBookmarks.map((bookmark) =>
      getAudiobookLocatorDetails(bookmark.locator, book?.audiobook?.manifest),
    )
  }, [book?.audiobook?.manifest, format, sortedBookmarks])

  const audiobookBookmarkTimestamps = useMemo(() => {
    if (format !== "audiobook") return []

    return (
      audiobookBookmarkDetails.map((details) =>
        formatTime(details.timestamp),
      ) ?? []
    )
  }, [audiobookBookmarkDetails, format])

  if (!bookmarks || !bookUuid) return null

  if (!bookmarks.length) {
    return (
      <Stack className="flex-1 items-center justify-center px-8 py-12">
        <Text className="text-muted-foreground text-center">
          No bookmarks yet! Try adding some by pressing the bookmark icon in the
          toolbar.
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
      {sortedBookmarks.map((bookmark, index) => (
        <Swipeable
          key={bookmark.uuid}
          renderRightActions={() => (
            <Button
              className="align-center h-full w-20 justify-center rounded-none sm:h-full sm:w-20"
              variant="destructive"
              onPress={() => {
                deleteBookmarks({
                  bookUuid: bookmark.bookUuid,
                  bookmarkUuids: [bookmark.uuid],
                })
              }}
            >
              <Icon as={Trash2} size={24} className="text-white" />
            </Button>
          )}
        >
          <View className="bg-background">
            <Button
              onPress={() => {
                dispatch(
                  bookmarkPressed({
                    bookUuid,
                    locator: bookmark.locator,
                    timestamp: Date.now(),
                    currentLocator: book?.position?.locator,
                  }),
                )
                onClose?.()
              }}
              variant="ghost"
              className="active:bg-secondary min-h-11 h-auto flex-col items-start rounded-none px-4 py-3 sm:h-auto"
            >
              {format === "audiobook" ? (
                <>
                  <Text className="text-[17px] font-normal">
                    {audiobookBookmarkDetails[index]?.title}
                  </Text>
                  <Text className="text-muted-foreground mt-0.5 text-[15px]">
                    Timestamp {audiobookBookmarkTimestamps[index]}
                  </Text>
                </>
              ) : (
                <>
                  <Text className="text-[17px] font-normal">
                    {bookmarkTitles[index]}
                  </Text>
                  <Text className="text-muted-foreground mt-0.5 text-[15px]">
                    Page {bookmarkPages[index]}
                  </Text>
                </>
              )}
            </Button>
            <View className="bg-border ml-4 h-px" />
          </View>
        </Swipeable>
      ))}
    </ScrollView>
  )
}
