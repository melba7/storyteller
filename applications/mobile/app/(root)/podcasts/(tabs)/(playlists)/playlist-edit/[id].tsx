// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PlaylistEditor } from "@/podcasts/PlaylistEditor"

export default function PlaylistEditRoute() {
  const { id } = useLocalSearchParams<{ id: string }>()
  return <PlaylistEditor id={id} />
}
