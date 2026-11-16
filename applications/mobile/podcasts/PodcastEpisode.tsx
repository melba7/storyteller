// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ActivityIndicator, ScrollView, View } from "react-native"

import { Text } from "@/components/ui/text"
import { formatDuration, formatEpisodeDate } from "@/modules/podcasts/library"

import { ScreenBar } from "./ScreenBar"
import { useEpisode, useShow } from "./hooks"

export function PodcastEpisode({ id }: { id: string }) {
  const episode = useEpisode(id)
  const show = useShow(episode.data?.showId ?? "")
  const current = episode.data

  const details = current
    ? [
        formatEpisodeDate(current.publishedAt),
        formatDuration(current.durationSeconds),
      ]
        .filter((part) => part !== "")
        .join(" · ")
    : ""

  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar title="Episode" />
      {episode.loading ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : !current ? (
        <Text className="text-muted-foreground px-8 py-12 text-center">
          {episode.error ?? "This episode isn't in your library."}
        </Text>
      ) : (
        <ScrollView contentContainerClassName="px-safe-or-4 pb-safe gap-3">
          <Text variant="h4">{current.title}</Text>
          {show.data ? (
            <Text className="text-muted-foreground">{show.data.title}</Text>
          ) : null}
          {details ? (
            <Text className="text-muted-foreground text-sm">{details}</Text>
          ) : null}
          <Text selectable className="text-base leading-6">
            {current.notes === ""
              ? "No notes for this episode."
              : current.notes}
          </Text>
        </ScrollView>
      )}
    </View>
  )
}
