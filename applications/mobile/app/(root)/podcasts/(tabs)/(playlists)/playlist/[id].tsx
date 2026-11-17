// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PlaylistPage } from "@/podcasts/PlaylistPage"

export default function PlaylistRoute() {
  const { id } = useLocalSearchParams<{ id: string }>()
  return <PlaylistPage id={id} />
}
