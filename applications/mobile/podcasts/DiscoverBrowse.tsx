// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import {
  Baby,
  BookOpen,
  Briefcase,
  Church,
  Clapperboard,
  Cpu,
  Fingerprint,
  FlaskConical,
  GraduationCap,
  HeartPulse,
  Landmark,
  Laugh,
  type LucideIcon,
  Music,
  Newspaper,
  Palette,
  Podcast,
  Scroll,
  Sofa,
  Trophy,
  Users,
} from "lucide-react-native"
import { ActivityIndicator, View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { categoryColors } from "@/modules/podcasts/categoryColors"
import { CHART_CATEGORIES, TOP_CHART } from "@/modules/podcasts/charts"
import { featuredCards } from "@/modules/podcasts/featured"
import { categoryHref } from "@/modules/podcasts/routes"

import { useOpenPreview } from "./ChartRow"
import { FeaturedCards } from "./FeaturedCards"
import { PressableScale } from "./PressableScale"
import { SectionHeader } from "./SectionHeader"
import { ShowShelf } from "./ShowShelf"
import { useChart, useForYou } from "./discoverHooks"

/** How many of the top chart the "Top Shows" shelf holds; the chart page has all of it. */
const TOP_SHELF = 25

/** One icon per Apple category id. A category without one gets the podcast icon. */
const CATEGORY_ICONS: Record<string, LucideIcon> = {
  "1301": Palette,
  "1321": Briefcase,
  "1303": Laugh,
  "1304": GraduationCap,
  "1483": BookOpen,
  "1511": Landmark,
  "1512": HeartPulse,
  "1487": Scroll,
  "1305": Baby,
  "1502": Sofa,
  "1310": Music,
  "1489": Newspaper,
  "1314": Church,
  "1533": FlaskConical,
  "1324": Users,
  "1545": Trophy,
  "1318": Cpu,
  "1488": Fingerprint,
  "1309": Clapperboard,
}

/**
 * What New shows, Apple's way: the featured cards, "Top Shows >" with ranks, "For You >"
 * (one shelf per category you follow) and the categories.
 */
export function DiscoverBrowse() {
  const router = useRouter()
  const segments = useSegments()
  const open = useOpenPreview()
  const forYou = useForYou()
  const top = useChart(TOP_CHART)
  const topShows = top.data ?? []
  const cards = featuredCards(topShows, forYou)
  return (
    <View className="pt-2">
      {top.loading ? (
        <ActivityIndicator
          className="mt-8"
          accessibilityLabel="Loading the top chart"
        />
      ) : top.error ? (
        <Text className="text-destructive px-4 pt-4 text-sm">{top.error}</Text>
      ) : null}

      {cards.length > 0 ? <FeaturedCards cards={cards} /> : null}

      {topShows.length > 0 ? (
        <>
          <SectionHeader
            title="Top Shows"
            onPress={() => router.push(categoryHref(TOP_CHART, segments))}
          />
          <ShowShelf
            shows={topShows.slice(0, TOP_SHELF).map((show, index) => ({
              key: show.appleId,
              imageUrl: show.imageUrl,
              title: show.title,
              caption: show.author,
              rank: index + 1,
              onPress: () => open(show.feedUrl),
            }))}
          />
        </>
      ) : null}

      {forYou.map((suggestion, index) => (
        <View key={suggestion.category.id}>
          <SectionHeader
            title={index === 0 ? "For You" : suggestion.category.name}
            onPress={() =>
              router.push(categoryHref(suggestion.category.id, segments))
            }
          />
          <Text className="text-muted-foreground -mt-2 mb-3 px-4 text-base">
            {index === 0 ? `${suggestion.category.name}. ` : ""}Because you
            follow {suggestion.because}
          </Text>
          <ShowShelf
            shows={suggestion.shows.map((show) => ({
              key: show.appleId,
              imageUrl: show.imageUrl,
              title: show.title,
              caption: show.author,
              onPress: () => open(show.feedUrl),
            }))}
          />
        </View>
      ))}

      <SectionHeader title="Categories" />
      <View className="px-4">
        <CategoryTiles />
      </View>
    </View>
  )
}

const GRID_GAP = 12
const TILE_RATIO = 0.6

/**
 * The categories as a two-column grid of tiles inside the screen's 16 pt gutters: a gradient
 * of the category's colour, its name in bold white at the bottom left and a large symbol in
 * a lighter shade at the top right. Each opens the category's chart.
 */
export function CategoryTiles() {
  const router = useRouter()
  const segments = useSegments()
  const { width } = useWindowDimensions()
  const tile = Math.max(1, Math.floor((width - 32 - GRID_GAP) / 2))
  return (
    <View className="flex-row flex-wrap" style={{ gap: GRID_GAP }}>
      {CHART_CATEGORIES.map((category) => {
        const { from, to, symbol } = categoryColors(category.id)
        const Symbol = CATEGORY_ICONS[category.id] ?? Podcast
        return (
          <PressableScale
            key={category.id}
            style={{ width: tile }}
            accessibilityRole="button"
            accessibilityLabel={`${category.name}, top podcasts`}
            onPress={() => router.push(categoryHref(category.id, segments))}
          >
            <View
              className="justify-end overflow-hidden rounded-xl p-3"
              style={{
                height: Math.round(tile * TILE_RATIO),
                backgroundImage: `linear-gradient(135deg, ${from}, ${to})`,
              }}
              accessible={false}
            >
              <View style={{ position: "absolute", top: 10, right: 10 }}>
                <Symbol
                  size={Math.round(tile * 0.36)}
                  strokeWidth={1.5}
                  color={symbol}
                />
              </View>
              <Text
                className="text-xl leading-6 font-bold text-white"
                numberOfLines={2}
              >
                {category.name}
              </Text>
            </View>
          </PressableScale>
        )
      })}
    </View>
  )
}
