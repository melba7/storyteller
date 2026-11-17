// LOFI-FORK: the podcasts section's last focused tab (see FORK.md).
//
// The player is a modal over the tabs, so its own route segments name no tab. The tab bar's
// layout tells this module which tab the listener is in, and the player builds its "Go to"
// links from it, so they open in that tab.

import { type TabGroup } from "./routes"

const TABS: readonly TabGroup[] = ["(home)", "(new)", "(library)", "(search)"]

let last: TabGroup | null = null

/** Remember the tab the route segments are in; segments with no tab change nothing. */
export function rememberTabFrom(segments: readonly string[]): void {
  const tab = TABS.find((name) => segments.includes(name))
  if (tab) last = tab
}

/** Segments that `tabBase` and the href helpers read as "the last tab" (Home at first). */
export function lastTabSegments(): readonly string[] {
  return last ? [last] : []
}

export function resetLastTab(): void {
  last = null
}
