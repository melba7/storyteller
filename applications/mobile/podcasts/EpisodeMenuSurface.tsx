// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { type SFSymbol } from "sf-symbols-typescript"

import { Menu, type MenuAction } from "@/components/ui/menu"
import {
  type MenuItem,
  type MenuLayout,
} from "@/modules/podcasts/episodeMenuModel"

import { type SurfaceProps } from "./episodeMenuSurface.types"

function action(item: MenuItem): MenuAction {
  return {
    id: item.id,
    title: item.title,
    image: item.icon as SFSymbol,
    ...(item.destructive ? { attributes: { destructive: true } } : {}),
  }
}

/** Where the menu cannot draw Apple's top row: the same entries in one list, in groups. */
export function layoutActions(
  layout: MenuLayout,
  onSelect: (id: string) => void,
) {
  const withPress = (item: MenuItem): MenuAction => ({
    ...action(item),
    onPress: () => onSelect(item.id),
  })
  return [
    ...layout.top.map(withPress),
    ...layout.groups.map((group, index) => ({
      id: `group-${index}`,
      title: "",
      displayInline: true,
      subactions: group.map(withPress),
    })),
  ]
}

export function EpisodeMenuSurface({
  layout,
  onSelect,
  children,
}: SurfaceProps) {
  return <Menu actions={layoutActions(layout, onSelect)}>{children}</Menu>
}
