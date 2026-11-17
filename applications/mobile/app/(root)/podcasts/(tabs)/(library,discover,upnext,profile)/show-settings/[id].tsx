// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { ShowSettingsScreen } from "@/podcasts/ShowSettingsScreen"

export default function ShowSettingsRoute() {
  const { id } = useLocalSearchParams<{ id: string }>()
  return <ShowSettingsScreen id={id} />
}
