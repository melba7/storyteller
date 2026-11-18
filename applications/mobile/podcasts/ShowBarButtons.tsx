// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"

import { saveShowSettings } from "@/modules/podcasts/dbSettings"
import {
  EPISODE_FILTERS,
  type EpisodeFilter,
} from "@/modules/podcasts/episodeRowLook"
import { type Show } from "@/modules/podcasts/library"
import { isLocalFeedUrl } from "@/modules/podcasts/localFiles"
import { showShare } from "@/modules/podcasts/share"
import { type EpisodeSort } from "@/modules/podcasts/showSettings"

import { shareContent } from "./ShareButton"

const SORTS: { id: EpisodeSort; title: string }[] = [
  { id: "newest", title: "Newest first" },
  { id: "oldest", title: "Oldest first" },
  { id: "shortest", title: "Shortest first" },
  { id: "longest", title: "Longest first" },
]

interface Options {
  show: Show
  archivedCount: number
  /** Which episodes the page lists now, and the way to change that. */
  filter: EpisodeFilter
  onFilter: (filter: EpisodeFilter) => void
  /** Starts picking several episodes. */
  onSelect: () => void
  /** Opens the show's settings. */
  onSettings: () => void
  /** Asks to unfollow (or, for the "Your files" show, delete it). */
  onUnfollow: () => void
}

/**
 * The show page's native toolbar items, one glass group at the right: a filter menu (Unplayed,
 * All Episodes, Downloaded, Saved, Archived), a sort menu (how the episodes are ordered and grouped,
 * kept per show) and a "…" menu with Select episodes, Share, Settings and Unfollow. It returns
 * the items themselves, not a component, because a toolbar finds its items by their type among
 * its direct children.
 */
export function showBarItems({
  show,
  archivedCount,
  filter,
  onFilter,
  onSelect,
  onSettings,
  onUnfollow,
}: Options) {
  const { settings } = show
  const save = (patch: Partial<typeof settings>) => {
    saveShowSettings(show.id, { ...settings, ...patch }).catch(
      (cause: unknown) => console.warn("Couldn't save the show's view", cause),
    )
  }
  return [
    <Stack.Toolbar.Menu
      key="filter"
      icon="line.3.horizontal.decrease"
      accessibilityLabel="Filter episodes"
    >
      {EPISODE_FILTERS.map((entry) => (
        <Stack.Toolbar.MenuAction
          key={entry.id}
          isOn={filter === entry.id}
          onPress={() => onFilter(entry.id)}
        >
          {entry.title}
        </Stack.Toolbar.MenuAction>
      ))}
    </Stack.Toolbar.Menu>,
    <Stack.Toolbar.Menu
      key="sort"
      icon="arrow.up.arrow.down"
      accessibilityLabel="Sort and group episodes"
    >
      <Stack.Toolbar.Menu inline title="Sort by">
        {SORTS.map((sort) => (
          <Stack.Toolbar.MenuAction
            key={sort.id}
            isOn={settings.sort === sort.id}
            onPress={() => save({ sort: sort.id })}
          >
            {sort.title}
          </Stack.Toolbar.MenuAction>
        ))}
      </Stack.Toolbar.Menu>
      <Stack.Toolbar.Menu inline title="Group">
        <Stack.Toolbar.MenuAction
          isOn={settings.groupBySeason}
          onPress={() => save({ groupBySeason: !settings.groupBySeason })}
        >
          Group by season
        </Stack.Toolbar.MenuAction>
        <Stack.Toolbar.MenuAction
          isOn={settings.showArchived}
          onPress={() => save({ showArchived: !settings.showArchived })}
        >
          {archivedCount > 0
            ? `Show archived (${archivedCount})`
            : "Show archived"}
        </Stack.Toolbar.MenuAction>
      </Stack.Toolbar.Menu>
    </Stack.Toolbar.Menu>,
    <Stack.Toolbar.Menu
      key="more"
      icon="ellipsis"
      accessibilityLabel="More for this show"
    >
      <Stack.Toolbar.MenuAction icon="checklist" onPress={onSelect}>
        Select episodes
      </Stack.Toolbar.MenuAction>
      <Stack.Toolbar.MenuAction
        icon="square.and.arrow.up"
        onPress={() => void shareContent(() => showShare(show))}
      >
        Share
      </Stack.Toolbar.MenuAction>
      <Stack.Toolbar.MenuAction icon="gearshape" onPress={onSettings}>
        Settings
      </Stack.Toolbar.MenuAction>
      <Stack.Toolbar.MenuAction
        icon="minus.circle"
        destructive
        onPress={onUnfollow}
      >
        {isLocalFeedUrl(show.feedUrl) ? "Delete show" : "Unfollow"}
      </Stack.Toolbar.MenuAction>
    </Stack.Toolbar.Menu>,
  ]
}
