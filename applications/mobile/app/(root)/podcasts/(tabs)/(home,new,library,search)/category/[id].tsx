// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { CategoryChart } from "@/podcasts/CategoryChart"

export default function CategoryChartScreen() {
  const { id } = useLocalSearchParams<{ id: string }>()
  return <CategoryChart id={id} />
}
