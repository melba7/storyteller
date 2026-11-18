// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { useHeaderHeight } from "expo-router/react-navigation"
import { StatusBar } from "expo-status-bar"
import { useEffect, useMemo, useRef, useState } from "react"
import { ActivityIndicator, FlatList, View } from "react-native"

import { Text } from "@/components/ui/text"
import { useIsFocused } from "@/hooks/useIsFocused"
import { fetchFeed, subscribe } from "@/modules/podcasts/dbFeeds"
import { normalizeFeedUrl } from "@/modules/podcasts/feedUrl"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { adoptFollowedPreview } from "@/modules/podcasts/playerInstance"
import {
  type EpisodeTarget,
  type Preview,
  findEpisodeIndex,
  previewFromFeed,
} from "@/modules/podcasts/preview"
import { showHref } from "@/modules/podcasts/routes"
import { showShare } from "@/modules/podcasts/share"

import { EpisodeRow } from "./EpisodeRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { shareContent } from "./ShareButton"
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
  // The list scrolls under the transparent header: a row scrolled to must land below it.
  const headerHeight = useHeaderHeight()
  const [preview, setPreview] = useState<Preview | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [following, setFollowing] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  // The bar's title appears once the picture at the top has scrolled under the bar.
  const titleBottom = useRef<number | null>(null)
  const [titleInBar, setTitleInBar] = useState(false)
  const left = useRef(false)
  // Following only moves on to the show's page while this page is still the one on screen.
  const isFocused = useIsFocused()
  const focused = useRef(isFocused)
  focused.current = isFocused
  const mounted = useRef(true)
  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
    }
  }, [])
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
    if (!feedUrl) {
      setError("No show was chosen. Go back and pick one.")
      return
    }
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
    // Marked done only when it runs: a header height change in between clears this timer, and
    // the next run sets a new one.
    const timer = setTimeout(() => {
      scrolled.current = true
      list.current?.scrollToIndex({
        index: target,
        animated: true,
        viewOffset: headerHeight,
      })
    }, 100)
    return () => clearTimeout(timer)
  }, [target, headerHeight])

  // Replaces this page with the show's own, once, when the show is in the library.
  useEffect(() => {
    if (followed && isFocused && !left.current) {
      left.current = true
      adoptFollowedPreview(followed.id).catch(() => {})
      router.replace(showHref(segments, followed.id))
    }
  }, [followed, isFocused, router, segments])

  async function follow() {
    if (following) return
    setFollowing(true)
    setProblem(null)
    try {
      const show = await subscribe(feedUrl)
      // A preview episode that is playing now has a library twin: keep its place there.
      await adoptFollowedPreview(show.id).catch(() => {})
      if (!left.current && mounted.current && focused.current) {
        left.current = true
        router.replace(showHref(segments, show.id))
      }
    } catch (cause) {
      setProblem(readableError(cause))
      setFollowing(false)
    }
  }

  return (
    <>
      {error ? (
        <BelowBar>
          <Text className="text-destructive px-8 py-12 text-center">
            {error}
          </Text>
        </BelowBar>
      ) : !preview ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : (
        <FlatList<StoredEpisode>
          ref={list}
          className="bg-background flex-1"
          onScrollToIndexFailed={({ averageItemLength, index }) => {
            // The row isn't drawn yet: go roughly there, then to the row itself.
            list.current?.scrollToOffset({
              offset: averageItemLength * index,
              animated: false,
            })
            setTimeout(
              () =>
                list.current?.scrollToIndex({
                  index,
                  animated: true,
                  viewOffset: headerHeight,
                }),
              150,
            )
          }}
          data={preview.episodes}
          keyExtractor={(episode) => episode.id}
          contentInsetAdjustmentBehavior="automatic"
          scrollEventThrottle={32}
          onScroll={(event) => {
            if (titleBottom.current === null) return
            setTitleInBar(
              event.nativeEvent.contentOffset.y + headerHeight >=
                titleBottom.current,
            )
          }}
          ListHeaderComponent={
            <>
              <ShowHeader
                show={preview.show}
                problem={problem}
                onFollow={follow}
                busy={following}
                episodes={preview.episodes}
                onTitleBottom={(bottom) => (titleBottom.current = bottom)}
              />
              <Text
                className="px-safe-or-4 pt-5 pb-2 text-[26px] font-bold"
                accessibilityRole="header"
              >
                Episodes
              </Text>
            </>
          }
          ListEmptyComponent={
            <Text className="text-muted-foreground px-safe-or-4 py-6 text-center text-sm">
              This feed has no episodes yet.
            </Text>
          }
          renderItem={({ item, index }) => (
            <View className="px-safe-or-4">
              <EpisodeRow
                artwork
                episode={item}
                show={preview.show}
                openable={false}
                highlighted={index === target}
              />
            </View>
          )}
        />
      )}
      {/* White clock and battery while the coloured header is under the bar. */}
      {preview && !titleInBar ? (
        <StatusBar style="light" verticalBarBehaviorIOS="disabled" />
      ) : null}
      <ScreenBar
        title={preview?.show.title ?? "Podcast"}
        titleHidden={Boolean(preview) && !titleInBar}
        right={
          preview ? (
            <Stack.Toolbar.Menu
              icon="ellipsis"
              accessibilityLabel="More for this show"
            >
              <Stack.Toolbar.MenuAction
                icon="plus.circle"
                disabled={following}
                onPress={() => void follow()}
              >
                Follow
              </Stack.Toolbar.MenuAction>
              <Stack.Toolbar.MenuAction
                icon="square.and.arrow.up"
                onPress={() => void shareContent(() => showShare(preview.show))}
              >
                Share
              </Stack.Toolbar.MenuAction>
            </Stack.Toolbar.Menu>
          ) : undefined
        }
      />
    </>
  )
}
