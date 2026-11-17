// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PodcastPreview } from "@/podcasts/PodcastPreview"

export default function PodcastPreviewScreen() {
  const { feed, guid, audio } = useLocalSearchParams<{
    feed: string
    guid?: string
    audio?: string
  }>()
  return <PodcastPreview feedUrl={feed} episode={{ guid, audioUrl: audio }} />
}
