// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PodcastPreview } from "@/podcasts/PodcastPreview"

export default function PodcastPreviewScreen() {
  const { feed, guid, audio, title } = useLocalSearchParams<{
    feed: string
    guid?: string
    audio?: string
    title?: string
  }>()
  return (
    <PodcastPreview feedUrl={feed} episode={{ guid, audioUrl: audio, title }} />
  )
}
