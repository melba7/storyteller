// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { Ellipsis } from "lucide-react-native"
import { useMemo } from "react"
import { ActivityIndicator, FlatList, Pressable, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import {
  downloadLook,
  formatStorage,
  sortDownloads,
} from "@/modules/podcasts/downloads"
import { type DownloadInfo } from "@/modules/podcasts/index"
import {
  type StoredEpisode,
  formatEpisodeDate,
} from "@/modules/podcasts/library"
import { episodeHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { DownloadButton } from "./DownloadButton"
import { ScreenBar } from "./ScreenBar"
import { useEpisodesByIds, useShows } from "./hooks"
import { confirmDelete, useDownloadMap, useStorageUsed } from "./useDownloads"

/**
 * The Downloads screen: the storage used at the top, then the downloaded and still-moving
 * episodes, newest first. Each row's menu deletes the download.
 */
export function Downloads() {
  const map = useDownloadMap()
  const storage = useStorageUsed()
  const list = useMemo(() => sortDownloads(Object.values(map)), [map])
  const ids = useMemo(() => list.map((info) => info.episodeId), [list])
  const episodes = useEpisodesByIds(ids)
  const shows = useShows()

  const byId = new Map(
    (episodes.data ?? []).map((episode) => [episode.id, episode]),
  )
  const showById = new Map((shows.data ?? []).map((show) => [show.id, show]))

  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar title="Downloads" />
      <FlatList<DownloadInfo>
        data={list}
        keyExtractor={(info) => info.episodeId}
        contentInsetAdjustmentBehavior="automatic"
        contentContainerClassName="px-safe-or-4 grow"
        ListHeaderComponent={
          <Text
            className="text-muted-foreground py-2 text-sm"
            accessibilityLabel={`Storage used, ${formatStorage(storage)}`}
          >
            Storage used: {formatStorage(storage)}
          </Text>
        }
        ListEmptyComponent={
          episodes.loading && ids.length > 0 ? (
            <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
          ) : (
            <Text className="text-muted-foreground px-8 py-12 text-center">
              No downloads yet. Tap the arrow on an episode to keep it on your
              phone.
            </Text>
          )
        }
        renderItem={({ item }) => {
          const episode = byId.get(item.episodeId)
          return (
            <DownloadRow
              info={item}
              episode={episode}
              artwork={
                episode?.imageUrl ??
                showById.get(episode?.showId ?? "")?.imageUrl ??
                null
              }
              showTitle={showById.get(episode?.showId ?? "")?.title ?? ""}
            />
          )
        }}
      />
    </View>
  )
}

function DownloadRow({
  info,
  episode,
  artwork,
  showTitle,
}: {
  info: DownloadInfo
  episode: StoredEpisode | undefined
  artwork: string | null
  showTitle: string
}) {
  const router = useRouter()
  const segments = useSegments()
  // A download whose episode left the library still shows, so it can be deleted.
  const title = episode?.title ?? "An episode no longer in your library"
  const look = downloadLook(info, title)
  const details = [
    showTitle,
    episode ? formatEpisodeDate(episode.publishedAt) : "",
    look.status,
  ]
    .filter((part) => part !== "")
    .join(" · ")
  const removable = { id: info.episodeId, title }
  return (
    <View className="border-border flex-row items-center gap-3 border-b py-3">
      <Pressable
        className="active:bg-secondary flex-1 flex-row items-center gap-3 rounded-md"
        accessibilityRole="button"
        accessibilityLabel={`${title}. ${details}`}
        disabled={!episode}
        onPress={() => router.push(episodeHref(segments, info.episodeId))}
      >
        <Artwork uri={artwork} size={56} />
        <View className="flex-1 gap-1">
          <Text className="font-semibold" numberOfLines={2}>
            {title}
          </Text>
          <Text className="text-muted-foreground text-sm" numberOfLines={2}>
            {details}
          </Text>
        </View>
      </Pressable>
      {episode ? <DownloadButton episode={episode} /> : null}
      <Menu
        actions={[
          {
            id: "delete",
            title:
              info.state === "downloaded"
                ? "Delete download"
                : "Remove download",
            attributes: { destructive: true },
            onPress: () => confirmDelete(removable),
          },
        ]}
      >
        <Button
          variant="ghost"
          size="icon"
          accessibilityLabel={`More for ${title}`}
        >
          <Icon as={Ellipsis} size={22} className="text-muted-foreground" />
        </Button>
      </Menu>
    </View>
  )
}
