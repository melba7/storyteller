// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ScrollView, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { HEADER_FALLBACK } from "@/modules/podcasts/artworkTint"
import {
  type FeaturedCard,
  featuredCardSize,
} from "@/modules/podcasts/featured"
import { cardPalette } from "@/modules/podcasts/homeLook"

import { Artwork } from "./Artwork"
import { useOpenPreview } from "./ChartRow"
import { PressableScale } from "./PressableScale"
import { useArtworkColor } from "./useWash"

const GUTTER = 16
const GAP = 12
/** The share of the square, at the bottom, that fades into the cover's colour. */
const FADE = 0.55

function Card({ card, size }: { card: FeaturedCard; size: number }) {
  const open = useOpenPreview()
  const { show } = card
  const color = useArtworkColor(
    { id: show.appleId, imageUrl: show.imageUrl, artworkColor: null },
    false,
  )
  const palette = cardPalette(color ?? HEADER_FALLBACK)
  const fade = Math.round(size * FADE)
  return (
    <PressableScale
      style={{ width: size, height: size }}
      accessibilityRole="button"
      accessibilityLabel={`${card.label.toLowerCase()}, ${show.title}${show.author ? `, ${show.author}` : ""}`}
      onPress={() => open(show.feedUrl)}
    >
      <View
        style={{
          width: size,
          height: size,
          borderRadius: 16,
          overflow: "hidden",
          backgroundColor: palette.background,
        }}
      >
        <Artwork
          uri={show.imageUrl}
          size={size}
          className="rounded-none border-0"
        />
        {/* The cover's lower part fades into its own colour. */}
        <View
          pointerEvents="none"
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: 0,
            height: fade + 1,
            backgroundImage: `linear-gradient(180deg, ${palette.background}00, ${palette.background})`,
          }}
        />
        <View
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: 0,
            maxHeight: size,
            paddingHorizontal: 16,
            paddingBottom: 16,
          }}
        >
          <Text
            className="text-[13px] font-semibold"
            style={{ color: palette.label }}
            numberOfLines={1}
          >
            {card.label}
          </Text>
          <Text
            className="mt-1 text-[26px] leading-8 font-bold"
            style={{ color: palette.text }}
            numberOfLines={2}
          >
            {show.title}
          </Text>
          {show.author ? (
            <Text
              className="mt-0.5 text-base"
              style={{ color: palette.text, opacity: 0.85 }}
              numberOfLines={1}
            >
              {show.author}
            </Text>
          ) : null}
        </View>
      </View>
    </PressableScale>
  )
}

/**
 * New's featured cards: a row that pages card by card, each a square filled by the
 * show's cover, whose lower part fades into its own colour under a grey caps label, the title
 * and the author. The next card peeks in at the right.
 */
export function FeaturedCards({ cards }: { cards: readonly FeaturedCard[] }) {
  const { width: window } = useWindowDimensions()
  const width = featuredCardSize(window)
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
        <Card key={card.show.appleId} card={card} size={width} />
      ))}
    </ScrollView>
  )
}
