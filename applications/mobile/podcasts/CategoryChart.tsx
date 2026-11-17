// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ActivityIndicator, FlatList, Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { CHART_CATEGORIES, type ChartShow } from "@/modules/podcasts/charts"

import { Artwork } from "./Artwork"
import { useOpenPreview } from "./ChartRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { useChart } from "./discoverHooks"

/** A category's top podcasts as a list, pushed from Discover. */
export function CategoryChart({ id }: { id: string }) {
  const category = CHART_CATEGORIES.find((c) => c.id === id)
  const chart = useChart(id)
  const open = useOpenPreview()
  return (
    <View className="bg-background flex-1">
      <ScreenBar title={category?.name ?? "Category"} />
      {!category ? (
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            This category isn&apos;t in the list.
          </Text>
        </BelowBar>
      ) : chart.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : chart.error ? (
        <BelowBar>
          <Text className="text-destructive px-8 py-12 text-center">
            {chart.error}
          </Text>
        </BelowBar>
      ) : (
        <FlatList<ChartShow>
          data={chart.data ?? []}
          keyExtractor={(show) => show.appleId}
          contentContainerClassName="px-safe-or-4 gap-3"
          contentInsetAdjustmentBehavior="automatic"
          ListEmptyComponent={
            <Text className="text-muted-foreground py-6 text-center text-sm">
              Nothing is on this chart right now.
            </Text>
          }
          renderItem={({ item, index }) => (
            <Pressable
              className="active:bg-secondary flex-row items-center gap-3 rounded-md py-1"
              accessibilityRole="button"
              accessibilityLabel={`${item.title}, number ${index + 1}`}
              onPress={() => open(item.feedUrl)}
            >
              <Text className="text-muted-foreground w-7 text-right">
                {index + 1}
              </Text>
              <Artwork uri={item.imageUrl} size={56} />
              <View className="flex-1">
                <Text className="font-semibold" numberOfLines={2}>
                  {item.title}
                </Text>
                {item.author ? (
                  <Text
                    className="text-muted-foreground text-sm"
                    numberOfLines={1}
                  >
                    {item.author}
                  </Text>
                ) : null}
              </View>
            </Pressable>
          )}
        />
      )}
    </View>
  )
}
