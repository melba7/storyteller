// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { View } from "react-native"

import { Text } from "@/components/ui/text"
import { type Show } from "@/modules/podcasts/library"
import { gridCellSize } from "@/modules/podcasts/pageFrame"
import { type RecentShow, updatedLabel } from "@/modules/podcasts/rooms"
import { type PodcastHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { PressableScale } from "./PressableScale"
import { ZoomLink } from "./ZoomLink"

/** The side of a cell in the grid, from the page frame's width and its number of columns. */
export function recentCellSize(layoutWidth: number, columns: number): number {
  return gridCellSize(layoutWidth, columns)
}

/**
 * One show in "Recently Updated": square rounded artwork, the title in bold and a grey line
 * from its newest episode's date, with a purple dot when it has new episodes.
 */
export function RecentCell({
  show,
  recent,
  size,
  now,
  href,
}: {
  show: Show
  recent: RecentShow
  size: number
  now: number
  href: PodcastHref
}) {
  const line = updatedLabel(recent.newestAt, now)
  const isNew = recent.unplayed > 0
  return (
    <ZoomLink href={href}>
      <PressableScale
        style={{ width: size }}
        accessibilityRole="button"
        accessibilityLabel={`${show.title}, ${line}${isNew ? ", new episodes" : ""}`}
      >
        <Artwork uri={show.imageUrl} size={size} />
        <Text className="mt-2 text-base font-bold" numberOfLines={1}>
          {show.title}
        </Text>
        <View className="flex-row items-center gap-1.5">
          {isNew ? <View className="bg-primary size-2 rounded-full" /> : null}
          <Text className="text-muted-foreground text-base" numberOfLines={1}>
            {line}
          </Text>
        </View>
      </PressableScale>
    </ZoomLink>
  )
}
