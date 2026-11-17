// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PodcastPreview } from "@/podcasts/PodcastPreview"

export default function PodcastPreviewScreen() {
  const { feed } = useLocalSearchParams<{ feed: string }>()
  return <PodcastPreview feedUrl={feed} />
}
