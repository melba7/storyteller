// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { useState } from "react"
import {
  ActivityIndicator,
  Alert,
  FlatList,
  RefreshControl,
  View,
} from "react-native"

import { Text } from "@/components/ui/text"
import { unsubscribe } from "@/modules/podcasts/db"
import { refreshShow } from "@/modules/podcasts/dbFeeds"
import {
  type EpisodeListItem,
  archivedCount,
  arrangeEpisodes,
} from "@/modules/podcasts/episodeList"
import { isLocalFeedUrl } from "@/modules/podcasts/localFiles"
import { readableError } from "@/modules/podcasts/nativeError"
import { tabBase } from "@/modules/podcasts/routes"

import { EpisodeRow } from "./EpisodeRow"
import { ScreenBar } from "./ScreenBar"
import { ShowBarButtons } from "./ShowBarButtons"
import { ShowHeader } from "./ShowHeader"
import { useEpisodes, useShow } from "./hooks"

export function PodcastShow({ id }: { id: string }) {
  const router = useRouter()
  const segments = useSegments()
  const show = useShow(id)
  const episodes = useEpisodes(id)
  const [refreshing, setRefreshing] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  async function refresh() {
    setRefreshing(true)
    setProblem(null)
    try {
      await refreshShow(id)
    } catch (cause) {
      setProblem(readableError(cause))
    } finally {
      setRefreshing(false)
    }
  }

  function confirmUnsubscribe(title: string) {
    const own = isLocalFeedUrl(show.data?.feedUrl ?? "")
    Alert.alert(
      own ? `Delete ${title}?` : `Unsubscribe from ${title}?`,
      own
        ? "Every file you added is deleted from this phone. The originals in the Files app stay."
        : "The show and its episodes are removed from your library.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: isLocalFeedUrl(show.data?.feedUrl ?? "")
            ? "Delete"
            : "Unsubscribe",
          style: "destructive",
          onPress: () => {
            unsubscribe(id).then(
              () => {
                // Back within this tab's stack, not into the other tab.
                if (router.canGoBack()) router.back()
                else router.navigate(tabBase(segments))
              },
              (cause: unknown) => setProblem(readableError(cause)),
            )
          },
        },
      ],
    )
  }

  const current = show.data
  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar
        title={current?.title ?? "Podcast"}
        right={
          current ? (
            <ShowBarButtons
              show={current}
              archivedCount={archivedCount(episodes.data ?? [])}
            />
          ) : undefined
        }
      />
      {show.loading ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : !current ? (
        <Text className="text-muted-foreground px-8 py-12 text-center">
          {show.error ?? "This show isn't in your library."}
        </Text>
      ) : (
        <FlatList<EpisodeListItem>
          data={arrangeEpisodes(episodes.data ?? [], current.settings)}
          keyExtractor={(item) => item.key}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={refresh} />
          }
          ListHeaderComponent={
            <ShowHeader
              show={current}
              problem={problem}
              onUnfollow={() => confirmUnsubscribe(current.title)}
            />
          }
          ListEmptyComponent={
            episodes.loading ? undefined : (
              <Text className="text-muted-foreground py-6 text-center text-sm">
                {episodes.error ?? "This feed has no episodes yet."}
              </Text>
            )
          }
          renderItem={({ item }) =>
            item.kind === "header" ? (
              <Text variant="h4" className="pt-4 pb-1">
                {item.title}
              </Text>
            ) : (
              <EpisodeRow episode={item.episode} show={current} />
            )
          }
        />
      )}
    </View>
  )
}
