// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Image } from "expo-image"
import { ScrollView, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { type ChartShow } from "@/modules/podcasts/charts"

import { Artwork } from "./Artwork"
import { useOpenPreview } from "./ChartRow"
import { PressableScale } from "./PressableScale"

/** How many of the top chart the carousel shows. */
export const HERO_COUNT = 5

const GUTTER = 16
const GAP = 12
const HEIGHT = 220
const ART = 140

/**
 * The top chart's first five as big cards that snap into place. Each card's blurred artwork
 * sits under a 60% black scrim, so its white text stays readable on any picture.
 */
export function HeroCarousel({ shows }: { shows: ChartShow[] }) {
  const { width } = useWindowDimensions()
  const open = useOpenPreview()
  const card = Math.max(1, width - GUTTER * 2)
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      snapToInterval={card + GAP}
      decelerationRate="fast"
      contentContainerStyle={{ gap: GAP, paddingHorizontal: GUTTER }}
      // The screen's own gutter is 16 pt, so the carousel runs edge to edge.
      style={{ marginHorizontal: -GUTTER }}
    >
      {shows.slice(0, HERO_COUNT).map((show, index) => (
        <PressableScale
          key={show.appleId}
          style={{ width: card, height: HEIGHT }}
          accessibilityRole="button"
          accessibilityLabel={`Number ${index + 1}, ${show.title}${show.author ? `, ${show.author}` : ""}`}
          onPress={() => open(show.feedUrl)}
        >
          <View
            className="bg-secondary flex-1 overflow-hidden rounded-3xl"
            accessible={false}
          >
            {show.imageUrl ? (
              <Image
                source={{ uri: show.imageUrl }}
                blurRadius={40}
                contentFit="cover"
                style={{ position: "absolute", width: "100%", height: "100%" }}
                accessibilityIgnoresInvertColors
              />
            ) : null}
            <View className="absolute inset-0 bg-black/60" />
            <View className="flex-1 flex-row items-center gap-4 p-4">
              <Artwork uri={show.imageUrl} size={ART} />
              <View className="flex-1 gap-1">
                <Text className="text-sm font-semibold text-white">
                  #{index + 1}
                </Text>
                <Text
                  className="text-xl font-bold text-white"
                  numberOfLines={3}
                >
                  {show.title}
                </Text>
                {show.author ? (
                  <Text className="text-sm text-white" numberOfLines={2}>
                    {show.author}
                  </Text>
                ) : null}
              </View>
            </View>
          </View>
        </PressableScale>
      ))}
    </ScrollView>
  )
}
