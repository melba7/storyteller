// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useState } from "react"

import { selectAll, toggleSelected } from "@/modules/podcasts/selection"

/** Multi-select state for an episode list: whether it is on, and which ids are picked. */
export function useSelection() {
  const [state, setState] = useState<{ on: boolean; selected: string[] }>({
    on: false,
    selected: [],
  })
  return {
    on: state.on,
    selected: state.selected,
    /** Turns selection on, optionally with one episode already picked (a long press). */
    begin: (id?: string) =>
      setState({ on: true, selected: id === undefined ? [] : [id] }),
    toggle: (id: string) =>
      setState((before) => ({
        on: true,
        selected: toggleSelected(before.selected, id),
      })),
    selectAll: (all: readonly string[]) =>
      setState((before) => ({
        on: true,
        selected: selectAll(before.selected, all),
      })),
    done: () => setState({ on: false, selected: [] }),
  }
}

export type Selection = ReturnType<typeof useSelection>
