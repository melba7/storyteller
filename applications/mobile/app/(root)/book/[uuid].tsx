import { Link, useLocalSearchParams, useRouter } from "expo-router"
import {
  ChevronDown,
  CircleX,
} from "lucide-react-native"
import { Fragment, useState } from "react"
import { RefreshControl, ScrollView, View } from "react-native"

import { SectionHeader } from "@/apple-look/SectionHeader"
import { BackButton } from "@/components/BackButton"
import BookDescription from "@/components/BookDescription"
import { BookThumbnailImage } from "@/components/BookThumbnail"
import { LoadingView } from "@/components/LoadingView"
import { MiniPlayerWidget } from "@/components/MiniPlayerWidget"
import { ScreenBackButton } from "@/components/ScreenBackButton"
import { Group } from "@/components/ui/Group"
import { Stack } from "@/components/ui/Stack"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import {
  Select,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Text } from "@/components/ui/text"
import { useAvailableFormats } from "@/hooks/useAvailableFormats"
import { useColorTheme } from "@/hooks/useColorTheme"
import { useDownloadedFormats } from "@/hooks/useDownloadedFormats"
import { useListAllServerBooks } from "@/hooks/useListAllServerBooks"
import { usesSystemHeader } from "@/lib/nativeChrome"
import {
  useCancelDownloadMutation,
  useDeleteBookMutation,
  useDownloadBookMutation,
  useGetBookQuery,
  useListStatusesQuery,
  useUpdateStatusMutation,
} from "@/store/localApi"
import { useLazyGetBookQuery as useLazyGetServerBookQuery } from "@/store/serverApi"
import type { UUID } from "@/uuid"

export default function BookDetailsScreen() {
  const router = useRouter()
  const { uuid } = useLocalSearchParams() as { uuid: UUID }
  const { foreground } = useColorTheme()

  const [downloadBook] = useDownloadBookMutation()
  const [cancelDownload] = useCancelDownloadMutation()
  const [deleteBook] = useDeleteBookMutation()
  const { data: book, isLoading, isUninitialized } = useGetBookQuery({ uuid })

  const { data: statuses } = useListStatusesQuery()

  const [updateStatus] = useUpdateStatusMutation()

  const [getServerBook, { isLoading: isServerLoading }] =
    useLazyGetServerBookQuery()

  const [showTagsMore, setShowTagsMore] = useState(false)
  const [showCollectionsMore, setShowCollectionsMore] = useState(false)
  const [pendingDeleteFormat, setPendingDeleteFormat] = useState<
    "readaloud" | "ebook" | "audiobook" | null
  >(null)

  const downloadedFormats = useDownloadedFormats(book)

  const availableFormats = useAvailableFormats(book)
  const onlyFormat = availableFormats[0]

  const { refetch } = useListAllServerBooks()

  if (isLoading || isUninitialized) return <LoadingView />

  if (!book) {
    return (
      <View className="flex-1 items-center justify-center">
        <Text>Book not found</Text>
        <Button
          accessibilityLabel="Go back"
          onPress={() => {
            if (router.canGoBack()) {
              router.back()
            } else {
              router.replace("/")
            }
          }}
        >
          <Text>Go back</Text>
        </Button>
      </View>
    )
  }

  const numberOfTagsToShow = 6
  const tagsMoreNeeded = book.tags.length > numberOfTagsToShow
  const tagsToShow = showTagsMore
    ? book.tags
    : book.tags.slice(0, numberOfTagsToShow)
  const numTagsHidden = book.tags.length - tagsToShow.length

  const numberOfCollectionsToShow = 6
  const collectionsMoreNeeded =
    book.collections.length > numberOfCollectionsToShow
  const collectionsToShow = showCollectionsMore
    ? book.collections
    : book.collections.slice(0, numberOfCollectionsToShow)
  const numCollectionsHidden =
    book.collections.length - collectionsToShow.length

  return (
    <View className="flex-1">
      {/* Contributes header options, it does not render a view. */}
      <ScreenBackButton />
      <ScrollView
        contentInsetAdjustmentBehavior={
          usesSystemHeader ? "automatic" : "never"
        }
        refreshControl={
          book.serverUuid ? (
            <RefreshControl
              refreshing={isServerLoading}
              onRefresh={() => {
                getServerBook({
                  serverUuid: book.serverUuid!,
                  bookUuid: book.uuid,
                })
              }}
            />
          ) : undefined
        }
      >
        <Stack className={usesSystemHeader ? "" : "pt-safe"}>
          {!usesSystemHeader && (
            <View className="px-safe-or-2 flex-row justify-between">
              <BackButton />
            </View>
          )}
          <Stack className="px-safe-or-5 items-start">
            <View className="mt-2 self-center rounded-xl shadow-xl shadow-black/20">
              <BookThumbnailImage book={book} height={352} width={232} />
            </View>
            <Text
              className="mt-6 mb-1 self-stretch text-center text-[28px] font-bold"
              variant="h1"
            >
              {book.title}
            </Text>
            {book.subtitle && (
              <Text className="text-muted-foreground mb-2 self-stretch text-center text-[17px]">
                {book.subtitle}
              </Text>
            )}
            <Stack className="mb-5 gap-1 self-stretch pl-0">
              <Group className="justify-center">
                <Text className="text-muted-foreground text-center text-[17px]">
                  by{" "}
                  {book.authors.map((author, index) => (
                    <Fragment key={author.uuid}>
                      <Link
                        href={{
                          pathname: "/author/[uuid]",
                          params: {
                            uuid: author.uuid,
                          },
                        }}
                        className="active:text-primary active:underline"
                      >
                        <Text className="text-primary text-[17px]">
                          {author.name}
                        </Text>
                      </Link>
                      <Text className="text-[17px]">
                        {index < book.authors.length - 1 && ", "}
                      </Text>
                    </Fragment>
                  ))}
                </Text>
              </Group>
              {!!book.narrators.length && (
                <Text className="text-muted-foreground text-center text-[15px]">
                  narrated by{" "}
                  {book.narrators.map((narrator, index) => (
                    <Fragment key={narrator.uuid}>
                      <Link
                        href={{
                          pathname: "/narrator/[uuid]",
                          params: {
                            uuid: narrator.uuid,
                          },
                        }}
                        className="active:text-primary active:underline"
                      >
                        <Text className="text-primary text-[15px]">
                          {narrator.name}
                        </Text>
                      </Link>
                      <Text className="text-[15px]">
                        {index < book.narrators.length - 1 && ", "}
                      </Text>
                    </Fragment>
                  ))}
                </Text>
              )}
            </Stack>
            <Group className="mb-6 flex-row flex-wrap items-center justify-center gap-3 self-stretch">
              {book.status && (
                <Select
                  value={{
                    value: book.status.uuid,
                    label: book.status.name,
                  }}
                  onValueChange={(option) => {
                    if (!option) return
                    updateStatus({
                      bookUuid: book.uuid,
                      statusUuid: option.value as UUID,
                    })
                  }}
                >
                  <SelectTrigger
                    accessibilityLabel={`Reading status, ${book.status.name}`}
                    iconColor="primary"
                    className="bg-primary/15 dark:bg-primary/15 dark:active:bg-primary/15 h-11 rounded-full border-0 px-5 shadow-none active:opacity-70"
                  >
                    <SelectValue placeholder="" />
                  </SelectTrigger>
                  {statuses?.map((status) => (
                    <SelectItem
                      key={status.uuid}
                      label={status.name}
                      value={status.uuid}
                    />
                  ))}
                </Select>
              )}
              <Stack className="gap-1">
                <Group>
                  {availableFormats.length > 1 ? (
                    <Menu
                      actions={availableFormats.map((format) => {
                        const status = book[format]?.downloadStatus
                        const isActiveDownload =
                          status === "DOWNLOADING" || status === "QUEUED"
                        const isDownloaded = downloadedFormats.includes(format)
                        const unavailable =
                          format !== "readaloud" &&
                          downloadedFormats.includes("readaloud")
                        const label = isDownloaded
                          ? `Remove ${format}`
                          : isActiveDownload
                            ? `Cancel ${format} download`
                            : `Download ${format}`

                        return {
                          id: `download-${format}`,
                          title: label,
                          ...(isDownloaded
                            ? { attributes: { destructive: true } }
                            : unavailable
                              ? { attributes: { disabled: true } }
                              : {}),
                          onPress: () => {
                            if (unavailable) return

                            if (isActiveDownload) {
                              cancelDownload({
                                bookUuid: book.uuid,
                                format,
                              })
                              return
                            }

                            if (isDownloaded) {
                              setPendingDeleteFormat(format)
                              return
                            }
                            downloadBook({
                              bookUuid: book.uuid,
                              format,
                            })
                          },
                        }
                      })}
                    >
                      <Button
                        variant="secondary"
                        accessibilityLabel="Open download options"
                      >
                        <Text>Downloads</Text>
                        <Icon
                          as={ChevronDown}
                          size={16}
                          className="text-primary"
                        />
                      </Button>
                    </Menu>
                  ) : (
                    onlyFormat && (
                      <>
                        <Button
                          variant={
                            book[onlyFormat]?.downloadStatus === "DOWNLOADED" ||
                            book[onlyFormat]?.downloadStatus === "DOWNLOADING" ||
                            book[onlyFormat]?.downloadStatus === "QUEUED"
                              ? "secondary"
                              : "default"
                          }
                          accessibilityLabel={
                            book[onlyFormat]?.downloadStatus === "DOWNLOADED"
                              ? `Remove ${onlyFormat}`
                              : book[onlyFormat]?.downloadStatus ===
                                    "DOWNLOADING" ||
                                  book[onlyFormat]?.downloadStatus === "QUEUED"
                                ? `Cancel ${onlyFormat} download`
                                : `Download ${onlyFormat}`
                          }
                          className={
                            book[onlyFormat]?.downloadStatus === "DOWNLOADED" ||
                            book[onlyFormat]?.downloadStatus ===
                              "DOWNLOADING" ||
                            book[onlyFormat]?.downloadStatus === "QUEUED"
                              ? "bg-destructive/15"
                              : ""
                          }
                          onPress={() => {
                            const status = book[onlyFormat]?.downloadStatus
                            if (
                              status === "DOWNLOADING" ||
                              status === "QUEUED"
                            ) {
                              cancelDownload({
                                bookUuid: book.uuid,
                                format: onlyFormat,
                              })
                              return
                            }

                            if (status === "DOWNLOADED") {
                              setPendingDeleteFormat(onlyFormat)
                              return
                            }

                            downloadBook({
                              bookUuid: book.uuid,
                              format: onlyFormat,
                            })
                          }}
                        >
                          <Text
                            className={
                              book[onlyFormat]?.downloadStatus ===
                                "DOWNLOADED" ||
                              book[onlyFormat]?.downloadStatus ===
                                "DOWNLOADING" ||
                              book[onlyFormat]?.downloadStatus === "QUEUED"
                                ? "text-destructive"
                                : "text-primary-foreground"
                            }
                          >
                            {book[onlyFormat]?.downloadStatus === "DOWNLOADED"
                              ? `Remove ${onlyFormat}`
                              : book[onlyFormat]?.downloadStatus ===
                                    "DOWNLOADING" ||
                                  book[onlyFormat]?.downloadStatus === "QUEUED"
                                ? "Cancel download"
                                : `Download ${onlyFormat}`}
                          </Text>
                          {(book[onlyFormat]?.downloadStatus ===
                            "DOWNLOADING" ||
                            book[onlyFormat]?.downloadStatus === "QUEUED") && (
                            <Icon
                              as={CircleX}
                              size={16}
                              className="text-destructive"
                            />
                          )}
                        </Button>
                      </>
                    )
                  )}
                </Group>
              </Stack>
            </Group>
            <View className="self-stretch">
              <BookDescription
                description={book.description}
                textColor={foreground}
                dom={{ matchContents: true }}
              />
            </View>
            {!!book.series.length && (
              <>
                <SectionHeader title="Series" className="mt-6 mb-2" />
                <Stack className="mb-2 self-stretch">
                  {book.series.map((series) => (
                    <Link
                      href={{
                        pathname: "/series/[uuid]",
                        params: { uuid: series.uuid },
                      }}
                      key={series.uuid}
                      asChild
                      className="w-full justify-start"
                    >
                      <Button
                        accessibilityLabel={`Open series ${series.name}, book ${series.position}`}
                        variant="link"
                        className="min-h-11 flex-row items-center justify-start gap-2 self-stretch px-0"
                      >
                        <Text className="text-primary text-[17px] font-normal">
                          {series.name}
                        </Text>
                        <Text className="text-muted-foreground text-[17px] font-normal">
                          #{series.position}
                        </Text>
                      </Button>
                    </Link>
                  ))}
                </Stack>
              </>
            )}
            {!!book.tags.length && (
              <>
                <SectionHeader title="Tags" className="mt-6 mb-3" />
                <Group className="mb-2 flex-wrap gap-2">
                  {tagsToShow.map((tag) => (
                    <Link
                      href={{
                        pathname: "/tag/[uuid]",
                        params: {
                          uuid: tag.uuid,
                        },
                      }}
                      key={tag.uuid}
                      asChild
                    >
                      <Button
                        accessibilityLabel={`Open tag ${tag.name}`}
                        variant="ghost"
                        size="sm"
                        className="bg-secondary flex flex-row items-center gap-2 rounded-full px-3.5"
                      >
                        <Text className="text-foreground text-[15px] font-normal">
                          {tag.name}
                        </Text>
                      </Button>
                    </Link>
                  ))}
                  {tagsMoreNeeded && (
                    <Button
                      variant="ghost"
                      size="sm"
                      className="flex flex-row items-center gap-1 rounded-full px-2"
                      accessibilityLabel={
                        showTagsMore
                          ? "Show fewer tags"
                          : `Show ${numTagsHidden} more tags`
                      }
                      onPress={() => {
                        setShowTagsMore(!showTagsMore)
                      }}
                    >
                      <Text className="text-primary text-[15px] font-semibold">
                        {showTagsMore ? "Less" : "More (" + numTagsHidden + ")"}
                      </Text>
                    </Button>
                  )}
                </Group>
              </>
            )}
            {!!book.collections.length && (
              <>
                <SectionHeader title="Collections" className="mt-6 mb-3" />
                <Group className="mb-2 flex-wrap gap-2">
                  {collectionsToShow.map((collection) => (
                    <Link
                      href={{
                        pathname: `/collection/[uuid]`,
                        params: { uuid: collection.uuid },
                      }}
                      key={collection.uuid}
                      asChild
                    >
                      <Button
                        accessibilityLabel={`Open collection ${collection.name}`}
                        variant="ghost"
                        size="sm"
                        className="bg-secondary flex flex-row items-center gap-2 rounded-full px-3.5"
                      >
                        <Text className="text-foreground text-[15px] font-normal">
                          {collection.name}
                        </Text>
                      </Button>
                    </Link>
                  ))}
                  {collectionsMoreNeeded && (
                    <Button
                      variant="ghost"
                      size="sm"
                      className="flex flex-row items-center gap-1 rounded-full px-2"
                      accessibilityLabel={
                        showCollectionsMore
                          ? "Show fewer collections"
                          : `Show ${numCollectionsHidden} more collections`
                      }
                      onPress={() => {
                        setShowCollectionsMore(!showCollectionsMore)
                      }}
                    >
                      <Text className="text-primary text-[15px] font-semibold">
                        {showCollectionsMore
                          ? "Less"
                          : "More (" + numCollectionsHidden + ")"}
                      </Text>
                    </Button>
                  )}
                </Group>
              </>
            )}
          </Stack>
        </Stack>
        {/* Spacer for the miniplayer */}
        <View className="h-40 w-full" />
      </ScrollView>
      <MiniPlayerWidget />
      <AlertDialog
        open={pendingDeleteFormat !== null}
        onOpenChange={(open) => {
          if (!open) setPendingDeleteFormat(null)
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Remove {pendingDeleteFormat} from device
            </AlertDialogTitle>
            <AlertDialogDescription>
              This will remove the downloaded {pendingDeleteFormat} files from
              your local device.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>
              <Text>Cancel</Text>
            </AlertDialogCancel>
            <AlertDialogAction asChild>
              <Button
                variant="destructive"
                accessibilityLabel={`Remove ${pendingDeleteFormat} from device`}
                onPress={() => {
                  if (!pendingDeleteFormat) return
                  deleteBook({
                    bookUuid: book.uuid,
                    format: pendingDeleteFormat,
                    deleteRecord: book.serverUuid === null,
                  }).then(() => {
                    // move back to main screen
                    router.replace("/")

                    refetch()
                  })
                  setPendingDeleteFormat(null)
                }}
              >
                <Text>Remove</Text>
              </Button>
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </View>
  )
}
