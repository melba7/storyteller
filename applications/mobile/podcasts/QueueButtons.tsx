import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Podcasts } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { isQueued, queuedLabel } from "@/modules/podcasts/upNext"

import { addToUpNext, removeQueued, useUpNext } from "./useUpNext"

/** Play next, Play last and (when queued) Remove, on the episode card. */
export function QueueButtons({
  episode,
  show,
}: {
  episode: StoredEpisode
  show: Show | null
}) {
  const queue = useUpNext()
  if (Podcasts === null) return null
  const queued = isQueued(queue, episode.id)
  return (
    <View className="w-full max-w-xs gap-2">
      {queued ? (
        <Text
          className="text-primary text-center text-sm font-semibold"
          accessibilityLabel={queuedLabel(queue, episode.id)}
        >
          In Up Next
        </Text>
      ) : null}
      <View className="flex-row gap-2">
        <Button
          variant="outline"
          className="flex-1 rounded-full"
          accessibilityLabel={`Play ${episode.title} next`}
          onPress={() => addToUpNext(episode, show, "next")}
        >
          <Text>Play next</Text>
        </Button>
        <Button
          variant="outline"
          className="flex-1 rounded-full"
          accessibilityLabel={`Play ${episode.title} last`}
          onPress={() => addToUpNext(episode, show, "last")}
        >
          <Text>Play last</Text>
        </Button>
      </View>
      {queued ? (
        <Button
          variant="ghost"
          accessibilityLabel={`Remove ${episode.title} from Up Next`}
          onPress={() => removeQueued(episode.id)}
        >
          <Text className="text-destructive">Remove from Up Next</Text>
        </Button>
      ) : null}
    </View>
  )
}
