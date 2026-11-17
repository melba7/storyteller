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

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { CHART_CATEGORIES, TOP_CHART } from "@/modules/podcasts/charts"
import { categoryHref } from "@/modules/podcasts/routes"

import { ChartRow } from "./ChartRow"
import { HERO_COUNT, HeroCarousel } from "./HeroCarousel"
import { PressableScale } from "./PressableScale"
import { useChart, useForYou } from "./discoverHooks"

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

/** What New shows: the hero cards, "For you", the top chart and the categories. */
export function DiscoverBrowse() {
  const forYou = useForYou()
  const top = useChart(TOP_CHART)
  return (
    <View className="gap-6">
      {top.loading ? (
        <ActivityIndicator accessibilityLabel="Loading the top chart" />
      ) : top.error ? (
        <Text className="text-destructive text-sm">{top.error}</Text>
      ) : top.data && top.data.length > 0 ? (
        <HeroCarousel shows={top.data} />
      ) : null}

      {forYou.map((suggestion) => (
        <ChartRow
          key={suggestion.category.id}
          title={`For you: ${suggestion.category.name}`}
          note={`Because you follow ${suggestion.because}`}
          shows={suggestion.shows}
        />
      ))}

      {top.data && top.data.length > HERO_COUNT ? (
        <ChartRow title="Top podcasts" shows={top.data.slice(HERO_COUNT)} />
      ) : null}

      <CategoryTiles />
    </View>
  )
}

/** The categories as a two-column grid of tiles; each opens the category's chart. */
export function CategoryTiles() {
  const router = useRouter()
  const segments = useSegments()
  const { width } = useWindowDimensions()
  // Two columns inside the screen's 16 pt gutters, with 12 pt between them.
  const tile = Math.max(1, Math.floor((width - 32 - 12) / 2))
  return (
    <View className="gap-3">
      <Text className="text-xl font-bold" accessibilityRole="header">
        Categories
      </Text>
      <View className="flex-row flex-wrap gap-3">
        {CHART_CATEGORIES.map((category) => (
          <PressableScale
            key={category.id}
            style={{ width: tile }}
            accessibilityRole="button"
            accessibilityLabel={`${category.name}, top podcasts`}
            onPress={() => router.push(categoryHref(category.id, segments))}
          >
            <View className="bg-secondary min-h-20 flex-row items-center gap-3 rounded-2xl p-3">
              <Icon
                as={CATEGORY_ICONS[category.id] ?? Podcast}
                size={24}
                className="text-primary"
              />
              <Text className="flex-1 font-semibold" numberOfLines={2}>
                {category.name}
              </Text>
            </View>
          </PressableScale>
        ))}
      </View>
    </View>
  )
}
