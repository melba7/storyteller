// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ScrollView, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { HEADER_FALLBACK, headerColors } from "@/modules/podcasts/artworkTint"
import { type FeaturedCard } from "@/modules/podcasts/featured"

import { Artwork } from "./Artwork"
import { useOpenPreview } from "./ChartRow"
import { PressableScale } from "./PressableScale"
import { useArtworkColor } from "./useWash"

const GUTTER = 16
const GAP = 12
/** How much of the next card peeks in at the right. */
const PEEK = 28
/** The image card is 3 wide to 2 tall, like Apple's. */
const RATIO = 2 / 3

function Card({ card, width }: { card: FeaturedCard; width: number }) {
  const open = useOpenPreview()
  const { show } = card
  const color = useArtworkColor(
    { id: show.appleId, imageUrl: show.imageUrl, artworkColor: null },
    false,
  )
  const height = Math.round(width * RATIO)
  return (
    <PressableScale
      style={{ width }}
      accessibilityRole="button"
      accessibilityLabel={`${card.label.toLowerCase()}, ${show.title}${show.author ? `, ${show.author}` : ""}`}
      onPress={() => open(show.feedUrl)}
    >
      <Text className="text-muted-foreground text-[15px] font-semibold">
        {card.label}
      </Text>
      <Text className="mt-1 text-[26px] leading-8 font-bold" numberOfLines={2}>
        {show.title}
      </Text>
      <View
        className="mt-3 items-center justify-center overflow-hidden rounded-xl"
        style={{
          height,
          backgroundColor:
            color === null ? HEADER_FALLBACK : headerColors(color).background,
        }}
      >
        <Artwork
          uri={show.imageUrl}
          size={Math.round(height * 0.72)}
          className="rounded-[10px]"
        />
      </View>
    </PressableScale>
  )
}

/**
 * New's featured cards: a row that pages card by card, each with a grey caps label, the
 * show's title as a headline and a wide image card (the artwork on a background of its own
 * colour). The next card peeks in at the right.
 */
export function FeaturedCards({ cards }: { cards: readonly FeaturedCard[] }) {
  const { width: window } = useWindowDimensions()
  const width = Math.max(1, window - GUTTER - PEEK - GAP)
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      decelerationRate="fast"
      snapToInterval={width + GAP}
      snapToAlignment="start"
      contentContainerStyle={{ paddingHorizontal: GUTTER, gap: GAP }}
    >
      {cards.map((card) => (
        <Card key={card.show.appleId} card={card} width={width} />
      ))}
    </ScrollView>
  )
}
