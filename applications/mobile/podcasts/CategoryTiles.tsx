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
import { View, useWindowDimensions } from "react-native"

import { Text } from "@/components/ui/text"
import { categoryColors } from "@/modules/podcasts/categoryColors"
import { CHART_CATEGORIES } from "@/modules/podcasts/charts"
import { categoryHref } from "@/modules/podcasts/routes"

import { PressableScale } from "./PressableScale"

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
