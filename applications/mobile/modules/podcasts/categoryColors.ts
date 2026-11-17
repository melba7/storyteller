// LOFI-FORK: the podcasts section's category colours (see FORK.md).
import { blendOver } from "./artworkTint"

/** One colour per Apple category id, in the family Apple Podcasts' Search tiles use. */
export const CATEGORY_COLORS: Readonly<Record<string, string>> = {
  "1301": "#d6436b", // Arts
  "1321": "#2f7fd8", // Business
  "1303": "#f0a020", // Comedy
  "1304": "#3aa0a8", // Education
  "1483": "#8a4fd0", // Fiction
  "1511": "#5a6b8a", // Government
  "1512": "#e0524a", // Health & Fitness
  "1487": "#a8742c", // History
  "1305": "#e86aa0", // Kids & Family
  "1502": "#3fae6a", // Leisure
  "1310": "#d63a4f", // Music
  "1489": "#3c8ef0", // News
  "1314": "#7a62c8", // Religion & Spirituality
  "1533": "#4aa832", // Science
  "1324": "#58a83a", // Society & Culture
  "1545": "#e8782a", // Sports
  "1318": "#3b5ee8", // Technology
  "1488": "#a83a3a", // True Crime
  "1309": "#2a2a30", // TV & Film
}

const FALLBACK = "#6b6b73"

/**
 * A tile's colours for a category: a lighter start (top left), a deeper end (bottom right)
 * and the shade of the large symbol, a little lighter than the middle of the tile.
 */
export function categoryColors(id: string): {
  from: string
  to: string
  symbol: string
} {
  const base = CATEGORY_COLORS[id] ?? FALLBACK
  return {
    from: blendOver("#ffffff", base, 0.18),
    to: blendOver("#000000", base, 0.22),
    symbol: blendOver("#ffffff", base, 0.3),
  }
}
