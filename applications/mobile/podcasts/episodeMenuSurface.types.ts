// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { type ReactElement } from "react"

import { type MenuLayout } from "@/modules/podcasts/episodeMenuModel"

export type SurfaceProps = {
  layout: MenuLayout
  /** Called with the id of the entry the listener chose. */
  onSelect: (id: string) => void
  /** A colour that tints the menu's symbols (the Home card's colour); the theme's if null. */
  tint?: string | undefined
  /** What the listener taps to open the menu. */
  children: ReactElement
}
