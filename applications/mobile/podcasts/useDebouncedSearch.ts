// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useRef, useState } from "react"

import { readableError } from "@/modules/podcasts/nativeError"

export type SearchState<T> = {
  results: T[]
  searching: boolean
  error: string | null
}

/**
 * Runs `search` for the words typed, after a short pause in typing. An answer that comes
 * back after newer words were typed is thrown away. Nothing runs for empty words.
 */
export function useDebouncedSearch<T>(
  term: string,
  search: (term: string) => Promise<T[]>,
  delayMs: number,
): SearchState<T> {
  const [state, setState] = useState<SearchState<T>>({
    results: [],
    searching: false,
    error: null,
  })
  const latest = useRef(0)
  const searchRef = useRef(search)
  searchRef.current = search

  useEffect(() => {
    const trimmed = term.trim()
    const run = ++latest.current
    if (trimmed === "") {
      setState({ results: [], searching: false, error: null })
      return
    }
    setState((old) => ({ ...old, searching: true }))
    const timer = setTimeout(() => {
      searchRef.current(trimmed).then(
        (results) => {
          if (run === latest.current) {
            setState({ results, searching: false, error: null })
          }
        },
        (cause: unknown) => {
          if (run === latest.current) {
            setState({
              results: [],
              searching: false,
              error: readableError(cause),
            })
          }
        },
      )
    }, delayMs)
    return () => clearTimeout(timer)
  }, [term, delayMs])

  return state
}
