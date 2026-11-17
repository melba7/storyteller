// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ScrollView, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"

import { Artwork } from "./Artwork"
import { PressableScale } from "./PressableScale"

export type ShelfShow = {
  key: string
  imageUrl: string | null
  /** The bold line under the artwork. */
  title: string
  /** The grey line under that; none when empty. */
  caption: string
  /** A chart position, drawn in bold at the left above the title; none when absent. */
  rank?: number
  onPress: () => void
}

/** A shelf of square artwork about 45% of the width across, rounded 10 pt, two lines under each. */
export function ShowShelf({ shows }: { shows: readonly ShelfShow[] }) {
  const { width: window } = useWindowDimensions()
  const size = Math.round(window * 0.45)
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      decelerationRate="fast"
      snapToInterval={size + 12}
      snapToAlignment="start"
      contentContainerStyle={{ paddingHorizontal: 16, gap: 12 }}
    >
      {shows.map((show) => (
        <PressableScale
          key={show.key}
          style={{ width: size }}
          accessibilityRole="button"
          accessibilityLabel={[
            show.rank === undefined ? "" : `Number ${show.rank}`,
            show.title,
            show.caption,
          ]
            .filter((part) => part !== "")
            .join(", ")}
          onPress={show.onPress}
        >
          <Artwork uri={show.imageUrl} size={size} className="rounded-[10px]" />
          <View className="mt-2">
            {show.rank === undefined ? null : (
              <Text
                className="text-lg font-bold"
                style={{ fontVariant: ["tabular-nums"] }}
              >
                {show.rank}
              </Text>
            )}
            <Text
              className={`text-lg ${show.rank === undefined ? "font-bold" : ""}`}
              numberOfLines={1}
            >
              {show.title}
            </Text>
            {show.caption ? (
              <Text className="text-muted-foreground text-lg" numberOfLines={1}>
                {show.caption}
              </Text>
            ) : null}
          </View>
        </PressableScale>
      ))}
    </ScrollView>
  )
}
