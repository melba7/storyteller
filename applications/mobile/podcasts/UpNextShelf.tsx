// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ScrollView, useWindowDimensions } from "react-native"

import { type ShelfEntry } from "@/modules/podcasts/home"
import { type Show } from "@/modules/podcasts/library"

import { UpNextCard, cardSize } from "./UpNextCard"

const GUTTER = 16
const GAP = 12

/**
 * Home's Up Next shelf: cards in a row that snaps card by card, the next one peeking in at
 * the right, a 16 pt gutter at the left.
 */
export function UpNextShelf({
  entries,
  showById,
}: {
  entries: readonly ShelfEntry[]
  showById: ReadonlyMap<string, Show>
}) {
  const { width: window } = useWindowDimensions()
  const { width, height } = cardSize(window)
  const now = Date.now()
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      decelerationRate="fast"
      snapToInterval={width + GAP}
      snapToAlignment="start"
      contentContainerStyle={{ paddingHorizontal: GUTTER, gap: GAP }}
    >
      {entries.map((entry) => {
        const show = showById.get(entry.episode.showId)
        return show ? (
          <UpNextCard
            key={entry.episode.id}
            entry={entry}
            show={show}
            width={width}
            height={height}
            now={now}
          />
        ) : null
      })}
    </ScrollView>
  )
}
