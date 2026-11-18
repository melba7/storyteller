// LOFI-FORK: the podcasts section's update-rhythm rule (see FORK.md).

const DAY = 24 * 3_600_000

/**
 * How often a show publishes, in one word: "Daily", "Weekly", "Biweekly" or "Monthly", from the
 * median gap between its six newest episodes. Empty with fewer than three dates, for a show
 * that has gone quiet (nothing for six months) or a rhythm that fits none. Home's "Updated
 * Weekly" and the show page's "Weekly" both come from here, so they always agree.
 */
export function cadenceWord(
  dates: readonly (number | null)[],
  now: number,
): string {
  const newest = dates
    .filter((date): date is number => date !== null && Number.isFinite(date))
    .sort((a, b) => b - a)
    .slice(0, 6)
  if (newest.length < 3) return ""
  if (now - (newest[0] ?? 0) > 180 * DAY) return ""
  const gaps = newest
    .slice(1)
    .map((date, i) => ((newest[i] ?? date) - date) / DAY)
    .sort((a, b) => a - b)
  const middle = Math.floor(gaps.length / 2)
  const median =
    gaps.length % 2 === 1
      ? (gaps[middle] ?? 0)
      : ((gaps[middle - 1] ?? 0) + (gaps[middle] ?? 0)) / 2
  if (median <= 2.5) return "Daily"
  if (median <= 9) return "Weekly"
  if (median <= 18) return "Biweekly"
  if (median <= 45) return "Monthly"
  return ""
}
