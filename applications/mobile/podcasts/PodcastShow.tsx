// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { EllipsisVertical } from "lucide-react-native"
import { useState } from "react"
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  View,
} from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import { refreshShow, unsubscribe } from "@/modules/podcasts/db"
import {
  type Show,
  type StoredEpisode,
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { episodeHref, tabBase } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { PlayButton } from "./PlayButton"
import { ScreenBar } from "./ScreenBar"
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
    Alert.alert(
      `Unsubscribe from ${title}?`,
      "The show and its episodes are removed from your library.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Unsubscribe",
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
            <Menu
              actions={[
                {
                  id: "unsubscribe",
                  title: "Unsubscribe",
                  attributes: { destructive: true },
                  onPress: () => confirmUnsubscribe(current.title),
                },
              ]}
            >
              <Button
                variant="ghost"
                size="icon"
                accessibilityLabel="Show options"
              >
                <Icon
                  as={EllipsisVertical}
                  size={24}
                  className="text-primary"
                />
              </Button>
            </Menu>
          ) : null
        }
      />
      {show.loading ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : !current ? (
        <Text className="text-muted-foreground px-8 py-12 text-center">
          {show.error ?? "This show isn't in your library."}
        </Text>
      ) : (
        <FlatList<StoredEpisode>
          data={episodes.data ?? []}
          keyExtractor={(episode) => episode.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={refresh} />
          }
          ListHeaderComponent={<Header show={current} problem={problem} />}
          ListEmptyComponent={
            episodes.loading ? undefined : (
              <Text className="text-muted-foreground py-6 text-center text-sm">
                {episodes.error ?? "This feed has no episodes yet."}
              </Text>
            )
          }
          renderItem={({ item }) => (
            <EpisodeRow episode={item} show={current} />
          )}
        />
      )}
    </View>
  )
}

function Header({ show, problem }: { show: Show; problem: string | null }) {
  const [expanded, setExpanded] = useState(false)
  return (
    <View className="gap-3 pb-4">
      <View className="flex-row items-center gap-4">
        <Artwork uri={show.imageUrl} size={112} />
        <View className="flex-1">
          <Text className="text-lg font-semibold">{show.title}</Text>
          {show.author ? (
            <Text className="text-muted-foreground">{show.author}</Text>
          ) : null}
        </View>
      </View>
      {show.description ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={
            expanded
              ? "Show less of the description"
              : "Show all of the description"
          }
          onPress={() => setExpanded((value) => !value)}
        >
          <Text className="text-sm" numberOfLines={expanded ? undefined : 4}>
            {show.description}
          </Text>
        </Pressable>
      ) : null}
      {problem ? (
        <Text className="text-destructive text-sm" accessibilityRole="alert">
          {problem}
        </Text>
      ) : null}
    </View>
  )
}

function EpisodeRow({ episode, show }: { episode: StoredEpisode; show: Show }) {
  const router = useRouter()
  const segments = useSegments()
  const details = [
    formatEpisodeDate(episode.publishedAt),
    formatEpisodeLength(episode),
  ]
    .filter((part) => part !== "")
    .join(" · ")
  return (
    <View
      className={`border-border flex-row items-center gap-3 border-b py-3 ${
        episode.played ? "opacity-50" : ""
      }`}
    >
      <Pressable
        className="active:bg-secondary flex-1 gap-1 rounded-md"
        accessibilityRole="button"
        accessibilityLabel={
          details ? `${episode.title}, ${details}` : episode.title
        }
        onPress={() => router.push(episodeHref(segments, episode.id))}
      >
        <Text className="font-semibold" numberOfLines={3}>
          {episode.title}
        </Text>
        {details ? (
          <Text className="text-muted-foreground text-sm">{details}</Text>
        ) : null}
      </Pressable>
      <PlayButton episode={episode} show={show} />
    </View>
  )
}
