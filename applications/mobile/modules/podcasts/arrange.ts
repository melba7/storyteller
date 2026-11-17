// LOFI-FORK: the podcasts section's arrange rules (see FORK.md).
//
// Pure maths for arranging shows by hand: moving one in a list, and which place a dragged
// row is over. Nothing here draws anything.

function clamp(index: number, length: number): number {
  return Math.max(0, Math.min(length - 1, index))
}

/** A new list with the item at `from` moved to `to`. Indexes outside the list are clamped. */
export function moveShow(ids: string[], from: number, to: number): string[] {
  if (ids.length === 0) return []
  const next = [...ids]
  const [moved] = next.splice(clamp(from, ids.length), 1)
  next.splice(clamp(to, ids.length), 0, moved as string)
  return next
}

/** The place a row that started at `start` is over after dragging it `translation` points. */
export function dropIndex(
  start: number,
  translation: number,
  rowHeight: number,
  count: number,
): number {
  if (count === 0) return 0
  return clamp(start + Math.round(translation / rowHeight), count)
}
