// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PodcastShow } from "@/podcasts/PodcastShow"

export default function PodcastShowScreen() {
  const { id } = useLocalSearchParams<{ id: string }>()
  return <PodcastShow id={id} />
}
