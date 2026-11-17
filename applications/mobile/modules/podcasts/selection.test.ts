// LOFI-FORK: the podcasts section's multi-select (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  bulkTargets,
  selectAll,
  selectionLabel,
  toggleSelected,
  upNextOrder,
} from "./selection"

const episode = (
  id: string,
  extra: Partial<{ played: boolean; archived: boolean; starred: boolean }> = {},
) => ({
  id,
  played: false,
  archived: false,
  starred: false,
  ...extra,
})

describe("toggleSelected", () => {
  it("adds an id that is not selected and removes one that is", () => {
    expect(toggleSelected(["a"], "b")).toEqual(["a", "b"])
    expect(toggleSelected(["a", "b"], "a")).toEqual(["b"])
  })
})

describe("selectAll", () => {
  it("selects every id, or none when all are already selected", () => {
    expect(selectAll([], ["a", "b"])).toEqual(["a", "b"])
    expect(selectAll(["a"], ["a", "b"])).toEqual(["a", "b"])
    expect(selectAll(["a", "b"], ["a", "b"])).toEqual([])
  })
})

describe("selectionLabel", () => {
  it("says how many are selected", () => {
    expect(selectionLabel(0)).toBe("Select episodes")
    expect(selectionLabel(1)).toBe("1 selected")
    expect(selectionLabel(4)).toBe("4 selected")
  })
})

describe("bulkTargets", () => {
  const list = [
    episode("a"),
    episode("b", { played: true }),
    episode("c", { archived: true }),
    episode("d", { starred: true }),
  ]

  it("marks played only the episodes that are not played", () => {
    expect(bulkTargets("played", list, new Set())).toEqual(["a", "c", "d"])
  })

  it("marks unplayed only the played ones", () => {
    expect(bulkTargets("unplayed", list, new Set())).toEqual(["b"])
  })

  it("archives the ones that are not archived, and unarchive does the reverse", () => {
    expect(bulkTargets("archive", list, new Set())).toEqual(["a", "b", "d"])
    expect(bulkTargets("unarchive", list, new Set())).toEqual(["c"])
  })

  it("stars the ones not starred, and unstars the starred", () => {
    expect(bulkTargets("star", list, new Set())).toEqual(["a", "b", "c"])
    expect(bulkTargets("unstar", list, new Set())).toEqual(["d"])
  })

  it("downloads the ones that are not archived, played or already on the phone", () => {
    expect(bulkTargets("download", list, new Set(["a"]))).toEqual(["d"])
  })

  it("queues every selected episode", () => {
    expect(bulkTargets("queueNext", list, new Set())).toEqual([
      "a",
      "b",
      "c",
      "d",
    ])
    expect(bulkTargets("queueLast", list, new Set())).toEqual([
      "a",
      "b",
      "c",
      "d",
    ])
  })
})

describe("upNextOrder", () => {
  it("adds to the bottom in the order shown", () => {
    expect(upNextOrder(["a", "b", "c"], "last")).toEqual([
      { id: "a", place: "last" },
      { id: "b", place: "last" },
      { id: "c", place: "last" },
    ])
  })

  it("adds to the top from the last one up, so they end up in the order shown", () => {
    expect(upNextOrder(["a", "b", "c"], "next")).toEqual([
      { id: "c", place: "next" },
      { id: "b", place: "next" },
      { id: "a", place: "next" },
    ])
  })
})
