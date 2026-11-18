// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { type Show } from "@/modules/podcasts/library"
import { badgeLabel } from "@/modules/podcasts/libraryView"
import { gridCellSize } from "@/modules/podcasts/pageFrame"
import { type PodcastHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { PressableScale } from "./PressableScale"
import { ZoomLink } from "./ZoomLink"

/** The grids' gutter around the cells and the gap between them, in points. */
export const GRID_GUTTER = 16
export const GRID_GAP = 12

/** The side of one grid cell, from the page frame's width and the number of columns. */
export function cellSize(layoutWidth: number, columns: number): number {
  return gridCellSize(layoutWidth, columns)
}

function label(show: Show, count: number): string {
  const name = show.author ? `${show.title}, ${show.author}` : show.title
  return count > 0 ? `${name}, ${count} unplayed` : name
}

/** The small pill with the unplayed count. Nothing at 0. */
function Badge({ count, className }: { count: number; className?: string }) {
  const text = badgeLabel(count)
  if (text === "") return null
  return (
    <View
      className={`bg-primary border-background min-h-5 min-w-5 items-center justify-center rounded-full border-2 px-1.5 ${className ?? ""}`}
    >
      <Text className="text-primary-foreground text-xs font-semibold">
        {text}
      </Text>
    </View>
  )
}

interface Props {
  show: Show
  count: number
  onPress: () => void
}

/** One show in a grid: its artwork with the badge on the top-right corner. */
export function ShowCell({
  show,
  count,
  size,
  onPress,
  href,
}: Props & {
  size: number
  /** Where the show's page is: the tile then zooms into it. */
  href?: PodcastHref
}) {
  const tile = (
    <PressableScale
      style={{ width: size, marginBottom: GRID_GAP }}
      accessibilityRole="button"
      accessibilityLabel={label(show, count)}
      {...(href ? {} : { onPress })}
    >
      <Artwork uri={show.imageUrl} size={size} />
      <Badge count={count} className="absolute -top-1.5 -right-1.5" />
    </PressableScale>
  )
  return href ? <ZoomLink href={href}>{tile}</ZoomLink> : tile
}

/** One show in the list: a row with the count at the right end. */
export function ShowRow({ show, count, onPress }: Props) {
  return (
    <Pressable
      className="active:bg-secondary flex-row items-center gap-3 rounded-md py-2"
      accessibilityRole="button"
      accessibilityLabel={label(show, count)}
      onPress={onPress}
    >
      <Artwork uri={show.imageUrl} size={56} />
      <View className="flex-1">
        <Text className="font-semibold" numberOfLines={2}>
          {show.title}
        </Text>
        {show.author ? (
          <Text className="text-muted-foreground text-sm" numberOfLines={1}>
            {show.author}
          </Text>
        ) : null}
      </View>
      <Badge count={count} />
    </Pressable>
  )
}
