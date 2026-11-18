// LOFI-FORK: the podcasts section's cover pictures (see FORK.md).

/** The picture widths the app asks Apple for. Few sizes keep the disk cache small. */
const BUCKETS = [160, 320, 640, 1280]

/** A phone never needs more than three pixels per point. */
const MAX_SCALE = 3

/** The last part of an Apple picture address, such as `100x100bb.png`. */
const SIZE_SEGMENT = /^\d+x\d+bb\.(png|jpg)$/

/** The smallest bucket that covers the wanted pixels, or the largest one. */
function bucketFor(points: number, scale: number): number {
  const safeScale =
    Number.isFinite(scale) && scale >= 1 ? Math.min(scale, MAX_SCALE) : 1
  const wanted = Number.isFinite(points) && points > 0 ? points * safeScale : 0
  return BUCKETS.find((bucket) => bucket >= wanted) ?? 1280
}

/** The Apple address with its size segment swapped for the bucket, or null if it isn't one. */
function rewriteApple(url: string, bucket: number): string | null {
  try {
    const parsed = new URL(url)
    if (!parsed.hostname.endsWith(".mzstatic.com")) return null
    const slash = parsed.pathname.lastIndexOf("/")
    if (!SIZE_SEGMENT.test(parsed.pathname.slice(slash + 1))) return null
    parsed.pathname = `${parsed.pathname.slice(0, slash + 1)}${bucket}x${bucket}bb.jpg`
    return parsed.toString()
  } catch {
    return null
  }
}

/**
 * The addresses to try for a cover drawn `points` wide on a screen with this scale, best
 * first. Only Apple's addresses can be resized; every other address comes back alone.
 */
export function artworkSources(
  url: string | null,
  points: number,
  scale: number,
): string[] {
  if (!url) return []
  const sharp = rewriteApple(url, bucketFor(points, scale))
  return sharp && sharp !== url ? [sharp, url] : [url]
}

/** The address to try after the one at `failedIndex` failed; the last one stays put. */
export function nextSource(sources: string[], failedIndex: number): number {
  return Math.max(0, Math.min(failedIndex + 1, sources.length - 1))
}
