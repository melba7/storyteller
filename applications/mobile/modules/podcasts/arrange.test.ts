// LOFI-FORK: the podcasts section's arrange rules (see FORK.md).
import { describe, expect, it } from "vitest"

import { dropIndex, moveShow } from "./arrange"

describe("moveShow", () => {
  const ids = ["a", "b", "c", "d"]

  it("moves a show down and up", () => {
    expect(moveShow(ids, 0, 2)).toEqual(["b", "c", "a", "d"])
    expect(moveShow(ids, 3, 1)).toEqual(["a", "d", "b", "c"])
  })
  it("returns a copy when nothing moves", () => {
    const same = moveShow(ids, 1, 1)
    expect(same).toEqual(ids)
    expect(same).not.toBe(ids)
  })
  it("clamps indexes that are out of range", () => {
    expect(moveShow(ids, 0, 99)).toEqual(["b", "c", "d", "a"])
    expect(moveShow(ids, 3, -5)).toEqual(["d", "a", "b", "c"])
    expect(moveShow(ids, 99, 0)).toEqual(["d", "a", "b", "c"])
    expect(moveShow(ids, -4, 1)).toEqual(["b", "a", "c", "d"])
  })
  it("handles an empty list", () => {
    expect(moveShow([], 0, 1)).toEqual([])
  })
})

describe("dropIndex", () => {
  it("stays put for a small drag and moves by whole rows", () => {
    expect(dropIndex(2, 10, 60, 5)).toBe(2)
    expect(dropIndex(2, 40, 60, 5)).toBe(3)
    expect(dropIndex(2, -100, 60, 5)).toBe(0)
  })
  it("stays inside the list", () => {
    expect(dropIndex(1, 9999, 60, 5)).toBe(4)
    expect(dropIndex(1, -9999, 60, 5)).toBe(0)
    expect(dropIndex(0, 0, 60, 0)).toBe(0)
  })
})
