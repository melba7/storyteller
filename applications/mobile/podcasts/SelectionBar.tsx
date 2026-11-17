// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useHeaderHeight } from "expo-router/react-navigation"
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Menu } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { type BulkAction, selectionLabel } from "@/modules/podcasts/selection"

import { runBulk } from "./bulk"
import { useDownloadMap } from "./useDownloads"
import { type Selection } from "./useSelection"

const ACTIONS: { id: BulkAction; title: string }[] = [
  { id: "download", title: "Download" },
  { id: "played", title: "Mark played" },
  { id: "unplayed", title: "Mark unplayed" },
  { id: "archive", title: "Archive" },
  { id: "unarchive", title: "Unarchive" },
  { id: "star", title: "Star" },
  { id: "unstar", title: "Unstar" },
  { id: "queueNext", title: "Play next (top of Up Next)" },
  { id: "queueLast", title: "Play last (bottom of Up Next)" },
]

/**
 * The bar over a list while episodes are being picked: how many, Select all, the actions
 * menu and Done. `episodes` is every episode in the list. It sits above the list, outside
 * any scroll view, so it starts below the transparent header.
 */
export function SelectionBar({
  selection,
  episodes,
  shows,
}: {
  selection: Selection
  episodes: readonly StoredEpisode[]
  shows: ReadonlyMap<string, Show>
}) {
  const headerHeight = useHeaderHeight()
  const downloads = useDownloadMap()
  const onPhone = new Set(
    Object.values(downloads)
      .filter((info) => info.state !== "failed")
      .map((info) => info.episodeId),
  )
  const picked = episodes.filter((episode) =>
    selection.selected.includes(episode.id),
  )
  return (
    <View
      className="px-safe-or-4 border-border flex-row items-center gap-1 border-b pb-1"
      style={{ paddingTop: headerHeight }}
    >
      <Text className="flex-1 font-semibold">
        {selectionLabel(selection.selected.length)}
      </Text>
      <Button
        variant="ghost"
        accessibilityLabel="Select all episodes"
        onPress={() => selection.selectAll(episodes.map((e) => e.id))}
      >
        <Text className="text-primary">All</Text>
      </Button>
      <Menu
        actions={ACTIONS.map((action) => ({
          id: action.id,
          title: action.title,
          onPress: () => {
            void runBulk(action.id, picked, shows, onPhone).then(() =>
              selection.done(),
            )
          },
        }))}
      >
        <Button
          variant="ghost"
          disabled={picked.length === 0}
          accessibilityLabel="Actions for the selected episodes"
        >
          <Text className="text-primary">Actions</Text>
        </Button>
      </Menu>
      <Button
        variant="ghost"
        accessibilityLabel="Finish selecting"
        onPress={selection.done}
      >
        <Text className="text-primary">Done</Text>
      </Button>
    </View>
  )
}
