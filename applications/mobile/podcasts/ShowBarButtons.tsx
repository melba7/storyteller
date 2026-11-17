// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { ArrowUpDown, Settings } from "lucide-react-native"
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { saveShowSettings } from "@/modules/podcasts/dbSettings"
import { type Show } from "@/modules/podcasts/library"
import { settingsHref } from "@/modules/podcasts/routes"
import { type EpisodeSort } from "@/modules/podcasts/showSettings"

const SORTS: { id: EpisodeSort; title: string }[] = [
  { id: "newest", title: "Newest first" },
  { id: "oldest", title: "Oldest first" },
  { id: "shortest", title: "Shortest first" },
  { id: "longest", title: "Longest first" },
]

/**
 * The show page's two buttons: how the episodes are ordered and grouped (kept per show), and
 * the show's settings.
 */
export function ShowBarButtons({
  show,
  archivedCount,
}: {
  show: Show
  archivedCount: number
}) {
  const router = useRouter()
  const segments = useSegments()
  const { settings } = show
  const save = (patch: Partial<typeof settings>) => {
    saveShowSettings(show.id, { ...settings, ...patch }).catch(
      (cause: unknown) => console.warn("Couldn't save the show's view", cause),
    )
  }
  return (
    <View className="flex-row items-center">
      <Menu
        actions={[
          ...SORTS.map((sort) => ({
            id: sort.id,
            title: sort.title,
            state:
              settings.sort === sort.id ? ("on" as const) : ("off" as const),
            onPress: () => save({ sort: sort.id }),
          })),
          {
            id: "season",
            title: "Group by season",
            state: settings.groupBySeason ? ("on" as const) : ("off" as const),
            onPress: () => save({ groupBySeason: !settings.groupBySeason }),
          },
          {
            id: "archived",
            title:
              archivedCount > 0
                ? `Show archived (${archivedCount})`
                : "Show archived",
            state: settings.showArchived ? ("on" as const) : ("off" as const),
            onPress: () => save({ showArchived: !settings.showArchived }),
          },
        ]}
      >
        <Button
          variant="ghost"
          size="icon"
          accessibilityLabel="Sort and group episodes"
        >
          <Icon as={ArrowUpDown} size={20} className="text-primary" />
        </Button>
      </Menu>
      <Button
        variant="ghost"
        size="icon"
        accessibilityLabel="Show settings"
        onPress={() => router.push(settingsHref(segments, show.id))}
      >
        <Icon as={Settings} size={20} className="text-primary" />
      </Button>
    </View>
  )
}
