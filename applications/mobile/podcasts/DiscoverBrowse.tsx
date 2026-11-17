// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { ChevronRight } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { CHART_CATEGORIES, TOP_CHART } from "@/modules/podcasts/charts"
import { categoryHref } from "@/modules/podcasts/routes"

import { ChartRow } from "./ChartRow"
import { useChart, useForYou } from "./discoverHooks"

/** What Discover shows under the search: "For you", the top chart and the categories. */
export function DiscoverBrowse() {
  const router = useRouter()
  const forYou = useForYou()
  const top = useChart(TOP_CHART)
  return (
    <View className="gap-5">
      {forYou.map((suggestion) => (
        <ChartRow
          key={suggestion.category.id}
          title={`For you: ${suggestion.category.name}`}
          note={`Because you follow ${suggestion.because}`}
          shows={suggestion.shows}
        />
      ))}

      {top.loading ? (
        <ActivityIndicator accessibilityLabel="Loading the top chart" />
      ) : top.error ? (
        <Text className="text-destructive text-sm">{top.error}</Text>
      ) : top.data && top.data.length > 0 ? (
        <ChartRow title="Top podcasts" shows={top.data} />
      ) : null}

      <View>
        <Text className="mb-1 font-semibold">Categories</Text>
        {CHART_CATEGORIES.map((category) => (
          <Pressable
            key={category.id}
            className="border-border active:bg-secondary flex-row items-center justify-between border-b py-3"
            accessibilityRole="button"
            accessibilityLabel={`${category.name}, top podcasts`}
            onPress={() => router.push(categoryHref(category.id))}
          >
            <Text>{category.name}</Text>
            <Icon
              as={ChevronRight}
              size={18}
              className="text-muted-foreground"
            />
          </Pressable>
        ))}
      </View>
    </View>
  )
}
