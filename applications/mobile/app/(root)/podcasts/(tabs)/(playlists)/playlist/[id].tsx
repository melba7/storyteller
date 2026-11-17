// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PlaylistScreen } from "@/podcasts/PlaylistScreen"

export default function PlaylistRoute() {
  const { id } = useLocalSearchParams<{ id: string }>()
  return <PlaylistScreen id={id} />
}
