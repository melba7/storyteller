// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ScrollView } from "react-native"

import { type ShelfEntry } from "@/modules/podcasts/home"
import { type Show } from "@/modules/podcasts/library"
import { upNextCardSize } from "@/modules/podcasts/pageFrame"

import { UpNextCard } from "./UpNextCard"
import { usePageFrame } from "./usePageFrame"

const GAP = 12

/**
 * Home's Up Next shelf: cards in a row that snaps card by card, the next one peeking in at
 * the right, a gutter (16 pt or the safe-area inset) at the left. A card is at most 300 pt wide.
 */
export function UpNextShelf({
  entries,
  showById,
}: {
  entries: readonly ShelfEntry[]
  showById: ReadonlyMap<string, Show>
}) {
  const frame = usePageFrame()
  const { width, height } = upNextCardSize(frame.width)
  const now = Date.now()
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      decelerationRate="fast"
      snapToInterval={width + GAP}
      snapToAlignment="start"
      contentContainerStyle={{
        paddingLeft: frame.left,
        paddingRight: frame.right,
        gap: GAP,
      }}
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
