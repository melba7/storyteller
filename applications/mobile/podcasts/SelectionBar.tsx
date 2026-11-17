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

/** How tall the bar is, so the list can leave room for it at the top. */
const BAR_HEIGHT = 48

/**
 * Room at the top of a list for the selection bar, which is drawn over the list (the list
 * has to be the screen's first child so the native bar can track it). Put it first in the
 * list's header while `selection.on`.
 */
export function SelectionSpacer() {
  return <View style={{ height: BAR_HEIGHT }} />
}

/**
 * The bar over a list while episodes are being picked: how many, Select all, the actions
 * menu and Done. `episodes` is every episode in the list. It is drawn after the list,
 * pinned just below the transparent header; the list leaves room with `SelectionSpacer`.
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
      className="bg-background px-safe-or-4 border-border absolute inset-x-0 flex-row items-center gap-1 border-b"
      style={{ top: headerHeight, height: BAR_HEIGHT }}
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
