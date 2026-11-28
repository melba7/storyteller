// LOFI-FORK: the podcasts section's episode maps from the Mac (see FORK.md).
//
// Fetches the Mac's map of the episode that plays, from the linked folder, and hands it to the
// native side (the rules are in episodeMap.ts). Called when an episode starts to play, after the
// exchange with the Mac that the same Play started, and every few minutes while it plays, so a map
// the Mac finishes in the middle of an episode is used from the next ad on. Never waited for, and
// nothing here throws. Not imported by any test, because the native modules are not there.
import { LofiScore } from "@/modules/lofi-score"

import {
  MAP_WAIT_MS,
  type MapSource,
  fetchEpisodeMap,
  mapTryAgain,
} from "./episodeMap"
import { Podcasts } from "./index"

// The episode whose map is looked for now, and the wait for its next try.
let wanted: string | null = null
let timer: ReturnType<typeof setTimeout> | null = null
// The maps the native side refused in this launch, by episode, so they are not read again.
const refused = new Set<string>()

function source(): MapSource | null {
  const native = Podcasts
  const folder = LofiScore
  if (!native || !folder) return null
  return {
    wanted: (id) => native.episodeMapWanted(id),
    read: (path) => folder.readLinkedFolderFileStatus(path),
    install: (id, text) => native.installEpisodeMap(id, text),
  }
}

async function attempt(episodeId: string, tries: number): Promise<void> {
  const from = source()
  if (!from) return
  const result = await fetchEpisodeMap(episodeId, from).catch(
    (cause: unknown) => {
      console.warn("Couldn't fetch the Mac's map of the episode", cause)
      return "none" as const
    },
  )
  if (result === "refused") {
    refused.add(episodeId)
    console.warn("The phone did not take the Mac's map of the episode")
  }
  if (!mapTryAgain(result, tries, wanted === episodeId)) return
  timer = setTimeout(() => {
    timer = null
    void attempt(episodeId, tries + 1)
  }, MAP_WAIT_MS)
}

/**
 * Looks for the map of the episode that plays now (`null`: nothing plays), and returns at once.
 * A look that was waiting for another episode's map is dropped.
 */
export function lookForEpisodeMap(episodeId: string | null): void {
  wanted = episodeId
  if (timer !== null) clearTimeout(timer)
  timer = null
  if (episodeId === null || refused.has(episodeId)) return
  void attempt(episodeId, 1)
}
