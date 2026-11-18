// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useCallback, useMemo, useState } from "react"

import { selectAll, toggleSelected } from "@/modules/podcasts/selection"

/**
 * Multi-select state for an episode list: whether it is on, and which ids are picked. The
 * object is the same one until the state changes, and its functions never change, so the
 * rows of a list can be memoized on it.
 */
export function useSelection() {
  const [state, setState] = useState<{ on: boolean; selected: string[] }>({
    on: false,
    selected: [],
  })
  /** Turns selection on, optionally with one episode already picked (a long press). */
  const begin = useCallback(
    (id?: string) =>
      setState({ on: true, selected: id === undefined ? [] : [id] }),
    [],
  )
  const toggle = useCallback(
    (id: string) =>
      setState((before) => ({
        on: true,
        selected: toggleSelected(before.selected, id),
      })),
    [],
  )
  const selectEvery = useCallback(
    (all: readonly string[]) =>
      setState((before) => ({
        on: true,
        selected: selectAll(before.selected, all),
      })),
    [],
  )
  const done = useCallback(() => setState({ on: false, selected: [] }), [])
  return useMemo(
    () => ({
      on: state.on,
      selected: state.selected,
      begin,
      toggle,
      selectAll: selectEvery,
      done,
    }),
    [state, begin, toggle, selectEvery, done],
  )
}

export type Selection = ReturnType<typeof useSelection>
