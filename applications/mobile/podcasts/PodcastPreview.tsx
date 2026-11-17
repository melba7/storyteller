// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { useEffect, useMemo, useRef, useState } from "react"
import { ActivityIndicator, FlatList, View } from "react-native"

import { Text } from "@/components/ui/text"
import { fetchFeed, subscribe } from "@/modules/podcasts/dbFeeds"
import { normalizeFeedUrl } from "@/modules/podcasts/feedUrl"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import {
  type EpisodeTarget,
  type Preview,
  findEpisodeIndex,
  previewFromFeed,
} from "@/modules/podcasts/preview"
import { showHref } from "@/modules/podcasts/routes"

import { EpisodeRow } from "./EpisodeRow"
import { ScreenBar } from "./ScreenBar"
import { ShowHeader } from "./ShowHeader"
import { useShows } from "./hooks"

function sameFeed(a: string, b: string): boolean {
  try {
    return normalizeFeedUrl(a) === normalizeFeedUrl(b)
  } catch {
    return a === b
  }
}

/**
 * A show read from its feed without saving it: the header with Follow, and the episodes
 * with Play. Following saves it and swaps this page for the show's own page. A show that is
 * already followed goes straight to its page.
 */
export function PodcastPreview({
  feedUrl,
  episode = {},
}: {
  feedUrl: string
  /** The episode a search result meant, to scroll to and mark. */
  episode?: EpisodeTarget
}) {
  const router = useRouter()
  const segments = useSegments()
  const shows = useShows()
  const [preview, setPreview] = useState<Preview | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [following, setFollowing] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const left = useRef(false)
  const list = useRef<FlatList<StoredEpisode>>(null)
  const scrolled = useRef(false)
  const { guid, audioUrl } = episode
  const target = useMemo(
    () =>
      preview ? findEpisodeIndex(preview.episodes, { guid, audioUrl }) : -1,
    [preview, guid, audioUrl],
  )

  useEffect(() => {
    let current = true
    setPreview(null)
    setError(null)
    fetchFeed(feedUrl).then(
      (feed) => {
        if (current) setPreview(previewFromFeed(feedUrl, feed))
      },
      (cause: unknown) => {
        if (current) setError(readableError(cause))
      },
    )
    return () => {
      current = false
    }
  }, [feedUrl])

  const followed = useMemo(
    () => shows.data?.find((show) => sameFeed(show.feedUrl, feedUrl)),
    [shows.data, feedUrl],
  )

  // Scrolls to the episode a search result meant, once the list is there.
  useEffect(() => {
    if (target < 0 || scrolled.current) return
    scrolled.current = true
    const timer = setTimeout(
      () => list.current?.scrollToIndex({ index: target, animated: true }),
      100,
    )
    return () => clearTimeout(timer)
  }, [target])

  // Replaces this page with the show's own, once, when the show is in the library.
  useEffect(() => {
    if (followed && !left.current) {
      left.current = true
      router.replace(showHref(segments, followed.id))
    }
  }, [followed, router, segments])

  async function follow() {
    if (following) return
    setFollowing(true)
    setProblem(null)
    try {
      const show = await subscribe(feedUrl)
      if (!left.current) {
        left.current = true
        router.replace(showHref(segments, show.id))
      }
    } catch (cause) {
      setProblem(readableError(cause))
      setFollowing(false)
    }
  }

  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar title={preview?.show.title ?? "Podcast"} />
      {error ? (
        <Text className="text-destructive px-8 py-12 text-center">{error}</Text>
      ) : !preview ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : (
        <FlatList<StoredEpisode>
          ref={list}
          onScrollToIndexFailed={({ averageItemLength, index }) => {
            // The row isn't drawn yet: go roughly there, then to the row itself.
            list.current?.scrollToOffset({
              offset: averageItemLength * index,
              animated: false,
            })
            setTimeout(
              () => list.current?.scrollToIndex({ index, animated: true }),
              150,
            )
          }}
          data={preview.episodes}
          keyExtractor={(episode) => episode.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          ListHeaderComponent={
            <ShowHeader
              show={preview.show}
              problem={problem}
              onFollow={follow}
              busy={following}
            />
          }
          ListEmptyComponent={
            <Text className="text-muted-foreground py-6 text-center text-sm">
              This feed has no episodes yet.
            </Text>
          }
          renderItem={({ item, index }) => (
            <EpisodeRow
              episode={item}
              show={preview.show}
              openable={false}
              highlighted={index === target}
            />
          )}
        />
      )}
    </View>
  )
}
