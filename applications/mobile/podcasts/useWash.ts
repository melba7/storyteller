// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"
import { useCSSVariable } from "uniwind"

import { ensureArtworkColor } from "@/modules/podcasts/artworkColor"
import { saveArtworkColor } from "@/modules/podcasts/db"
import { headerWash, washStyle } from "@/modules/podcasts/headerWash"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show } from "@/modules/podcasts/library"

/**
 * The show's artwork colour for its page. A show opened without one is measured here, and
 * saved when `persist` is on (a library show; a preview's show isn't in the database). The
 * colour is null until it is known, and then the page simply has no wash.
 */
export function useArtworkColor(
  show: Pick<Show, "id" | "imageUrl" | "artworkColor"> | null,
  persist = true,
): string | null {
  const [measured, setMeasured] = useState<{
    id: string
    color: string
  } | null>(null)
  const known = show?.artworkColor ?? null
  const id = show?.id
  const imageUrl = show?.imageUrl
  useEffect(() => {
    if (id === undefined || known || !imageUrl) return
    let live = true
    const native = Podcasts
    ensureArtworkColor(
      { id, imageUrl, artworkColor: null },
      native
        ? {
            measure: (url) => native.artworkColor(url),
            save: persist ? saveArtworkColor : () => Promise.resolve(),
          }
        : null,
    ).then(
      (color) => {
        if (live && color) setMeasured({ id, color })
      },
      (cause: unknown) => console.warn("Couldn't measure the artwork", cause),
    )
    return () => {
      live = false
    }
  }, [id, known, imageUrl, persist])
  if (known) return known
  return measured && measured.id === id ? measured.color : null
}

/**
 * The style of a wash view for this artwork colour in the current theme, or null when there
 * is no colour yet.
 */
export function useWashStyle(color: string | null) {
  const background = useCSSVariable("--color-background") as string
  const foreground = useCSSVariable("--color-foreground") as string
  if (!color) return null
  return washStyle(color, headerWash(color, background, foreground), background)
}
