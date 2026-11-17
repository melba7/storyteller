// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator, ScrollView, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { formatDuration, formatEpisodeDate } from "@/modules/podcasts/library"

import { pressEpisode, useEpisodeStatus } from "./PlayButton"
import { ScreenBar } from "./ScreenBar"
import { useEpisode, useShow } from "./hooks"

export function PodcastEpisode({ id }: { id: string }) {
  const episode = useEpisode(id)
  const show = useShow(episode.data?.showId ?? "")
  const current = episode.data
  const status = useEpisodeStatus(id)

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
        <ScrollView
          contentContainerClassName="px-safe-or-4 gap-3"
          contentInsetAdjustmentBehavior="automatic"
        >
          <Text variant="h4">{current.title}</Text>
          {show.data ? (
            <Text className="text-muted-foreground">{show.data.title}</Text>
          ) : null}
          {details ? (
            <Text className="text-muted-foreground text-sm">{details}</Text>
          ) : null}
          <Button
            className="self-start"
            accessibilityLabel={status === "playing" ? "Pause" : "Play"}
            onPress={() => pressEpisode(current, show.data ?? null, status)}
          >
            <Icon
              as={status === "playing" ? Pause : Play}
              size={18}
              className="text-primary-foreground"
            />
            <Text>
              {status === "playing"
                ? "Pause"
                : current.positionSeconds > 0 && !current.played
                  ? "Resume"
                  : "Play"}
            </Text>
          </Button>
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
