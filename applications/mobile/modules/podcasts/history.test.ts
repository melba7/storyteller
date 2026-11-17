// LOFI-FORK: the podcasts section's listening history (see FORK.md).
import { describe, expect, it } from "vitest"

import { dayTitle, groupByDay } from "./history"

// 15 Nov 2026, 14:00 in the phone's time zone.
const now = new Date(2026, 10, 15, 14, 0).getTime()
const at = (day: number, hour: number) =>
  new Date(2026, 10, day, hour, 0).getTime()

describe("dayTitle", () => {
  it("calls the same day Today and the day before Yesterday", () => {
    expect(dayTitle(at(15, 1), now)).toBe("Today")
    expect(dayTitle(at(14, 23), now)).toBe("Yesterday")
  })

  it("writes older days out", () => {
    expect(dayTitle(at(10, 9), now)).toBe("10 Nov 2026")
  })
})

describe("groupByDay", () => {
  it("groups episodes listened to on the same day, keeping their order", () => {
    const episodes = [
      { id: "a", lastPlayedAt: at(15, 13) },
      { id: "b", lastPlayedAt: at(15, 9) },
      { id: "c", lastPlayedAt: at(14, 20) },
      { id: "d", lastPlayedAt: at(2, 8) },
    ]
    expect(
      groupByDay(episodes, now).map((group) => [
        group.title,
        group.episodes.map((e) => e.id),
      ]),
    ).toEqual([
      ["Today", ["a", "b"]],
      ["Yesterday", ["c"]],
      ["2 Nov 2026", ["d"]],
    ])
  })

  it("gives nothing for no episodes", () => {
    expect(groupByDay([], now)).toEqual([])
  })
})
