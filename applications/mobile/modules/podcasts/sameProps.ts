// LOFI-FORK: the podcasts section's row comparison (see FORK.md).
//
// An episode row on a long list is memoized. Every time the library is read again the
// screens get new objects, so an episode with the same fields arrives as a new object and
// `memo`'s own comparison would see a change in every row. This compares data field by
// field instead. It looks at every field both sides have, so a field nobody thought of can
// only make two rows differ (one draw too many) and never make them equal (a stale row).

/** How deep into nested data it looks. Deeper than this counts as different. */
const MAX_DEPTH = 6

const DAY_MS = 24 * 60 * 60 * 1000

function isPlain(value: object): boolean {
  const prototype: unknown = Object.getPrototypeOf(value)
  return prototype === Object.prototype || prototype === null
}

function fieldsOf(value: object): (string | symbol)[] {
  return Reflect.ownKeys(value)
}

/**
 * True when both sides are the same value (`Object.is`) or are plain data, arrays and plain
 * objects, that hold the same values in every field. A function, a date, a map or any other
 * object is the same only when it is the very same one.
 */
export function sameData(a: unknown, b: unknown, depth = 0): boolean {
  if (Object.is(a, b)) return true
  if (depth >= MAX_DEPTH) return false
  if (typeof a !== "object" || typeof b !== "object") return false
  if (a === null || b === null) return false
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b)) return false
    if (a.length !== b.length) return false
    return a.every((item, at) => sameData(item, b[at], depth + 1))
  }
  if (!isPlain(a) || !isPlain(b)) return false
  const keys = fieldsOf(a)
  if (keys.length !== fieldsOf(b).length) return false
  return keys.every(
    (key) =>
      Object.prototype.hasOwnProperty.call(b, key) &&
      sameData(
        (a as Record<string | symbol, unknown>)[key],
        (b as Record<string | symbol, unknown>)[key],
        depth + 1,
      ),
  )
}

/** For `memo`: the props of two draws are the same when every prop holds the same data. */
export function sameProps<P extends object>(before: P, after: P): boolean {
  return sameData(before, after)
}

/**
 * Whether `dateWords` says "5m ago" or "3h ago" for an episode, which is true for its first
 * day and changes as time passes, so a row that says it cannot be skipped.
 */
export function saysTimeAgo(publishedAt: number | null, now: number): boolean {
  if (publishedAt === null) return false
  const age = now - publishedAt
  return age >= 0 && age < DAY_MS
}

/**
 * For the memo of an episode row: the props are the same, and the row does not say how long
 * ago its episode came out (it draws with its list while that is still counting).
 */
export function sameRowProps<
  P extends { episode: { publishedAt: number | null } },
>(before: P, after: P, now: number = Date.now()): boolean {
  return (
    !saysTimeAgo(after.episode.publishedAt, now) && sameProps(before, after)
  )
}
