// LOFI-FORK: the podcasts section's stats rules (see FORK.md). Swift counts the time (it has
// to, with the screen locked); these rules only read what it sends and shape it for the screen.

/** What Swift's `getStats` sends, in seconds. Days are the phone's local days "yyyy-MM-dd". */
export type Stats = {
  listened: number
  savedBySpeed: number
  savedBySkipping: number
  savedByTrim: number
  savedByAds: number
  savedByChapters: number
  /** How many ads were skipped, and how many of those skips were undone or found too far. */
  adSkips: number
  adUndone: number
  adTooFar: number
  days: Record<string, number>
}

export type SavedRow = { key: string; label: string; seconds: number }

export type DayBar = {
  key: string
  label: string
  seconds: number
  /** 0 to 1, of the busiest day. A day with any listening is never quite flat. */
  height: number
  /** Only a few days carry their label, so 30 bars stay readable. */
  showLabel: boolean
}

const DAY = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/
const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
]

function good(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : 0
}

/** A count: a whole number above zero. */
function goodCount(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : 0
}

/** Reads the native stats; anything that is not a good number is 0. */
export function readStats(raw: unknown): Stats {
  const object = (raw && typeof raw === "object" ? raw : {}) as Partial<
    Record<keyof Stats, unknown>
  >
  const days: Record<string, number> = {}
  const given = object.days
  if (given && typeof given === "object" && !Array.isArray(given)) {
    for (const [key, value] of Object.entries(given)) {
      if (DAY.test(key) && good(value) > 0) days[key] = good(value)
    }
  }
  return {
    listened: good(object.listened),
    savedBySpeed: good(object.savedBySpeed),
    savedBySkipping: good(object.savedBySkipping),
    savedByTrim: good(object.savedByTrim),
    savedByAds: good(object.savedByAds),
    savedByChapters: good(object.savedByChapters),
    adSkips: goodCount(object.adSkips),
    adUndone: goodCount(object.adUndone),
    adTooFar: goodCount(object.adTooFar),
    days,
  }
}

/** "3 h 12 min", "45 min", "2 h", "under 1 min" or "0 min". */
export function formatDuration(seconds: number): string {
  const total = good(seconds)
  if (total === 0) return "0 min"
  if (total < 30) return "under 1 min"
  const minutes = Math.round(total / 60)
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  if (hours === 0) return `${rest} min`
  return rest === 0 ? `${hours} h` : `${hours} h ${rest} min`
}

export function savedRows(stats: Stats): SavedRow[] {
  return [
    { key: "speed", label: "Speed", seconds: stats.savedBySpeed },
    {
      key: "skipping",
      label: "Intros and outros",
      seconds: stats.savedBySkipping,
    },
    { key: "trim", label: "Trimmed silence", seconds: stats.savedByTrim },
    { key: "ads", label: "Skipped ads", seconds: stats.savedByAds },
    {
      key: "chapters",
      label: "Skipped chapters",
      seconds: stats.savedByChapters,
    },
  ]
}

export function totalSaved(stats: Stats): number {
  return savedRows(stats).reduce((sum, row) => sum + row.seconds, 0)
}

function pad(value: number): string {
  return value < 10 ? `0${value}` : String(value)
}

/** The local day of `date` as "yyyy-MM-dd". */
export function dayKey(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

/** The last `count` local days ending with `today`, oldest first, with bar heights. */
export function lastDays(
  days: Record<string, number>,
  today: Date,
  count = 30,
): DayBar[] {
  const bars: DayBar[] = []
  for (let back = count - 1; back >= 0; back--) {
    // Built from the calendar parts so a daylight saving change can't skip or repeat a day.
    const date = new Date(
      today.getFullYear(),
      today.getMonth(),
      today.getDate() - back,
    )
    const key = dayKey(date)
    bars.push({
      key,
      label: `${date.getDate()} ${MONTHS[date.getMonth()]}`,
      seconds: good(days[key]),
      height: 0,
      showLabel: back % 10 === 0,
    })
  }
  const busiest = Math.max(0, ...bars.map((bar) => bar.seconds))
  return bars.map((bar) => ({
    ...bar,
    height:
      busiest > 0
        ? Math.max(bar.seconds / busiest, bar.seconds > 0 ? 0.04 : 0)
        : 0,
  }))
}
