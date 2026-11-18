// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { FlatList, PixelRatio, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import {
  SHELF_GAP,
  SHELF_GUTTER,
  SHELF_MAX_TEXT_SCALE,
  shelfHeight,
  shelfTextScale,
  shelfTileSize,
} from "@/modules/podcasts/homeLook"
import { type PodcastHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { PressableScale } from "./PressableScale"
import { ZoomLink } from "./ZoomLink"

export type ShelfShow = {
  key: string
  imageUrl: string | null
  /** The bold line under the artwork. */
  title: string
  /** The grey line under that; none when empty. */
  caption: string
  /** A chart position, drawn in bold at the left above the title; none when absent. */
  rank?: number
  /** A followed show's page: the tile zooms into it. A preview has none and uses `onPress`. */
  href?: PodcastHref
  onPress?: () => void
}

/**
 * A shelf of square artwork about 45% of the width across, rounded 10 pt, two lines under each.
 * A horizontal list: it draws a few tiles at first and more as it scrolls, and its fixed tile
 * length keeps the snapping exact.
 */
export function ShowShelf({ shows }: { shows: readonly ShelfShow[] }) {
  const { width: window } = useWindowDimensions()
  const size = shelfTileSize(window)
  // The texts grow with the system text size, up to 1.2 times; the height follows, and is the
  // loading shelf's height, so the page does not jump when the shows arrive.
  const ranked = shows.some((show) => show.rank !== undefined)
  const height = shelfHeight(
    size,
    ranked,
    shelfTextScale(PixelRatio.getFontScale()),
  )
  return (
    <FlatList
      style={{ height, flexGrow: 0 }}
      horizontal
      data={shows}
      keyExtractor={(show) => show.key}
      showsHorizontalScrollIndicator={false}
      decelerationRate="fast"
      snapToInterval={size + SHELF_GAP}
      snapToAlignment="start"
      contentContainerStyle={{ paddingHorizontal: SHELF_GUTTER }}
      ItemSeparatorComponent={() => <View style={{ width: SHELF_GAP }} />}
      getItemLayout={(_, index) => ({
        length: size,
        offset: SHELF_GUTTER + index * (size + SHELF_GAP),
        index,
      })}
      initialNumToRender={3}
      maxToRenderPerBatch={3}
      windowSize={5}
      renderItem={({ item: show }) => {
        const tile = (
          <PressableScale
            style={{ width: size }}
            accessibilityRole="button"
            accessibilityLabel={[
              show.rank === undefined ? "" : `Number ${show.rank}`,
              show.title,
              show.caption,
            ]
              .filter((part) => part !== "")
              .join(", ")}
            {...(show.href ? {} : { onPress: show.onPress })}
          >
            <Artwork
              uri={show.imageUrl}
              size={size}
              className="rounded-[10px]"
            />
            <View className="mt-2">
              {show.rank === undefined ? null : (
                <Text
                  maxFontSizeMultiplier={SHELF_MAX_TEXT_SCALE}
                  className="text-lg font-bold"
                  style={{ fontVariant: ["tabular-nums"] }}
                >
                  {show.rank}
                </Text>
              )}
              <Text
                maxFontSizeMultiplier={SHELF_MAX_TEXT_SCALE}
                className={`text-lg ${show.rank === undefined ? "font-bold" : ""}`}
                numberOfLines={1}
              >
                {show.title}
              </Text>
              {show.caption ? (
                <Text
                  maxFontSizeMultiplier={SHELF_MAX_TEXT_SCALE}
                  className="text-muted-foreground text-lg"
                  numberOfLines={1}
                >
                  {show.caption}
                </Text>
              ) : null}
            </View>
          </PressableScale>
        )
        return show.href ? <ZoomLink href={show.href}>{tile}</ZoomLink> : tile
      }}
    />
  )
}
