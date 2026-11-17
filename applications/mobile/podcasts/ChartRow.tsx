// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { ScrollView, View } from "react-native"

import { Text } from "@/components/ui/text"
import { type ChartShow } from "@/modules/podcasts/charts"
import { previewHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { PressableScale } from "./PressableScale"

export const TILE = 140

/** Opens a chart show's preview in the tab you are in. */
export function useOpenPreview() {
  const router = useRouter()
  const segments = useSegments()
  return (feedUrl: string) => router.push(previewHref(segments, feedUrl))
}

/** One show in a row: its picture, title and, when given, a line under it. */
export function ShowTile({ show, note }: { show: ChartShow; note?: string }) {
  const open = useOpenPreview()
  return (
    <PressableScale
      style={{ width: TILE }}
      accessibilityRole="button"
      accessibilityLabel={`${show.title}${show.author ? `, ${show.author}` : ""}`}
      onPress={() => open(show.feedUrl)}
    >
      <Artwork uri={show.imageUrl} size={TILE} />
      <Text className="mt-1 text-sm font-semibold" numberOfLines={2}>
        {show.title}
      </Text>
      {note ? (
        <Text className="text-muted-foreground text-xs" numberOfLines={2}>
          {note}
        </Text>
      ) : null}
    </PressableScale>
  )
}

/** A heading with a row of show tiles that scrolls sideways. */
export function ChartRow({
  title,
  shows,
  note,
}: {
  title: string
  shows: ChartShow[]
  note?: string
}) {
  return (
    <View className="gap-2">
      <Text className="text-xl font-bold" accessibilityRole="header">
        {title}
      </Text>
      {note ? (
        <Text className="text-muted-foreground -mt-1 text-sm">{note}</Text>
      ) : null}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerClassName="gap-3"
      >
        {shows.map((show) => (
          <ShowTile key={show.appleId} show={show} />
        ))}
      </ScrollView>
    </View>
  )
}
