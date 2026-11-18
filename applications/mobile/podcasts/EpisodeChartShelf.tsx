// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { FlatList, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import {
  EPISODE_COVER,
  EPISODE_ROWS,
  EPISODE_ROW_HEIGHT,
  EPISODE_SHELF_HEIGHT,
  SHELF_GAP,
  SHELF_GUTTER,
  episodeColumnWidth,
  pagesOfRows,
} from "@/modules/podcasts/homeLook"
import { previewHref } from "@/modules/podcasts/routes"
import { type ChartEpisode } from "@/modules/podcasts/topEpisodes"

import { Artwork } from "./Artwork"
import { PressableScale } from "./PressableScale"

type Ranked = { episode: ChartEpisode; rank: number }

const LINE = { fontSize: 15, lineHeight: 20 }
/**
 * The rows are a fixed 76 pt, so their text may grow only to 1.2 times (3 lines of 24 pt fit).
 * Past that the lines would overlap the next row.
 */
const MAX_SCALE = 1.2

/**
 * Apple's episode chart as pages of three ranked rows, side by side, each page a little
 * narrower than the window so the next one peeks in. A row has the cover, the rank in bold,
 * the title on up to two lines and the show's name under it; it opens the show's preview at
 * that episode. A horizontal list, so only the pages near the screen are drawn.
 */
export function EpisodeChartShelf({
  episodes,
}: {
  episodes: readonly ChartEpisode[]
}) {
  const router = useRouter()
  const segments = useSegments()
  const { width: window } = useWindowDimensions()
  const width = episodeColumnWidth(window)
  const pages = pagesOfRows(
    episodes.map((episode, index): Ranked => ({ episode, rank: index + 1 })),
  )
  return (
    <FlatList
      horizontal
      data={pages}
      keyExtractor={(page) => page[0]!.episode.episodeId}
      showsHorizontalScrollIndicator={false}
      decelerationRate="fast"
      snapToInterval={width + SHELF_GAP}
      snapToAlignment="start"
      contentContainerStyle={{ paddingHorizontal: SHELF_GUTTER }}
      ItemSeparatorComponent={() => <View style={{ width: SHELF_GAP }} />}
      getItemLayout={(_, index) => ({
        length: width,
        offset: SHELF_GUTTER + index * (width + SHELF_GAP),
        index,
      })}
      initialNumToRender={2}
      maxToRenderPerBatch={2}
      windowSize={5}
      renderItem={({ item: page }) => (
        <View style={{ width, height: EPISODE_SHELF_HEIGHT }}>
          {page.map(({ episode, rank }) => (
            <PressableScale
              key={episode.episodeId}
              accessibilityRole="button"
              accessibilityLabel={`${episode.title}, ${episode.showName}, number ${rank}`}
              style={{
                height: EPISODE_ROW_HEIGHT,
                flexDirection: "row",
                alignItems: "center",
                gap: 12,
              }}
              onPress={() =>
                router.push(
                  previewHref(segments, episode.feedUrl, {
                    title: episode.title,
                  }),
                )
              }
            >
              <Artwork
                uri={episode.imageUrl}
                size={EPISODE_COVER}
                className="rounded-[8px]"
              />
              <Text
                maxFontSizeMultiplier={MAX_SCALE}
                className="w-6 text-center font-bold"
                style={[LINE, { fontVariant: ["tabular-nums"] }]}
              >
                {rank}
              </Text>
              <View style={{ flex: 1 }}>
                <Text
                  maxFontSizeMultiplier={MAX_SCALE}
                  numberOfLines={2}
                  style={LINE}
                >
                  {episode.title}
                </Text>
                <Text
                  maxFontSizeMultiplier={MAX_SCALE}
                  className="text-muted-foreground"
                  numberOfLines={1}
                  style={LINE}
                >
                  {episode.showName}
                </Text>
              </View>
            </PressableScale>
          ))}
        </View>
      )}
    />
  )
}

/** The loading shelf: grey rows of the real shelf's exact height. Hidden from VoiceOver. */
export function EpisodeShelfSkeleton() {
  const { width: window } = useWindowDimensions()
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      style={{
        height: EPISODE_SHELF_HEIGHT,
        width: episodeColumnWidth(window) + SHELF_GUTTER,
        overflow: "hidden",
        paddingLeft: SHELF_GUTTER,
      }}
    >
      {Array.from({ length: EPISODE_ROWS }, (_, i) => (
        <View
          key={i}
          style={{
            height: EPISODE_ROW_HEIGHT,
            flexDirection: "row",
            alignItems: "center",
            gap: 12,
          }}
        >
          <View
            className="bg-secondary rounded-[8px]"
            style={{ width: EPISODE_COVER, height: EPISODE_COVER }}
          />
          <View style={{ flex: 1, gap: 8 }}>
            <View className="bg-secondary h-4 w-4/5 rounded-full" />
            <View className="bg-secondary h-4 w-3/5 rounded-full" />
          </View>
        </View>
      ))}
    </View>
  )
}
