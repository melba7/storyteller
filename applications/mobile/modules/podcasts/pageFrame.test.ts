// LOFI-FORK: the podcasts section's page sizes (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  GUTTER,
  categoryColumns,
  chunkRows,
  gridCellSize,
  gridColumns,
  pageFrame,
  showHeaderSide,
  upNextCardSize,
} from "./pageFrame"

describe("pageFrame", () => {
  it("keeps the 16 pt gutters when there are no insets, as on a portrait iPhone", () => {
    expect(pageFrame(390, { left: 0, right: 0 })).toEqual({
      left: 16,
      right: 16,
      width: 390,
    })
    // A portrait iPhone's side insets are 0, so nothing changes there.
    expect(pageFrame(390, { left: 0, right: 0 }).width).toBe(390)
  })

  it("grows each side to its own inset and narrows the width by the extra", () => {
    // A phone in landscape: 62 pt at the island side, 34 at the other.
    expect(pageFrame(852, { left: 62, right: 34 })).toEqual({
      left: 62,
      right: 34,
      width: 852 - 62 - 34 + 32,
    })
  })

  it("handles the folded Duo's one-sided strip", () => {
    const frame = pageFrame(400, { left: 0, right: 60 })
    expect(frame.left).toBe(GUTTER)
    expect(frame.right).toBe(60)
    // The width the helpers expect: what is left between the gutters, plus their 32 pt.
    expect(frame.width - 32).toBe(400 - 16 - 60)
  })

  it("never returns less than 1 pt of width", () => {
    expect(pageFrame(40, { left: 100, right: 100 }).width).toBe(1)
  })
})

describe("showHeaderSide", () => {
  it("is the window's width on a portrait phone", () => {
    expect(showHeaderSide(390, 844)).toBe(390)
    expect(showHeaderSide(430, 932)).toBe(430)
    expect(showHeaderSide(375, 667)).toBe(375)
  })

  it("is capped at 430 on a wide window", () => {
    expect(showHeaderSide(1024, 1366)).toBe(430)
  })

  it("is at most 60% of the height, so a landscape phone's header is not two screens", () => {
    expect(showHeaderSide(852, 393)).toBe(Math.round(393 * 0.6))
  })

  it("is a nearly square open Duo's 60% of its height", () => {
    expect(showHeaderSide(700, 720)).toBe(430)
    expect(showHeaderSide(700, 600)).toBe(360)
  })

  it("is never below 1", () => {
    expect(showHeaderSide(0, 0)).toBe(1)
  })
})

describe("upNextCardSize", () => {
  it("is two thirds of the width on phones, so they are unchanged", () => {
    expect(upNextCardSize(390)).toEqual({ width: 257, height: 344 })
    expect(upNextCardSize(430)).toEqual({ width: 284, height: 381 })
  })

  it("is capped at 300 wide on a wide window", () => {
    expect(upNextCardSize(852)).toEqual({ width: 300, height: 402 })
    expect(upNextCardSize(1024).width).toBe(300)
  })

  it("leaves the cards of a tall phone as they are", () => {
    expect(upNextCardSize(390, 844)).toEqual({ width: 257, height: 344 })
    expect(upNextCardSize(430, 932)).toEqual({ width: 284, height: 381 })
    expect(upNextCardSize(375, 667)).toEqual({ width: 248, height: 332 })
  })

  it("keeps a card above the mini player on a short window, such as the folded Duo", () => {
    // 466 x 678 pt: the card would be 402 tall, so its buttons sat under the mini player.
    expect(upNextCardSize(466, 678)).toEqual({ width: 263, height: 353 })
  })

  it("never makes a card smaller than 300 tall, even in landscape", () => {
    expect(upNextCardSize(852, 393)).toEqual({ width: 224, height: 300 })
  })
})

describe("categoryColumns", () => {
  it("is two on every phone width in portrait", () => {
    for (const width of [320, 375, 390, 430]) {
      expect(categoryColumns(width)).toBe(2)
    }
  })

  it("adds columns as the window gets wider", () => {
    expect(categoryColumns(852)).toBe(4)
    expect(categoryColumns(1024)).toBeGreaterThan(categoryColumns(626))
    expect(categoryColumns(626)).toBeGreaterThanOrEqual(3)
  })
})

describe("gridColumns", () => {
  it("keeps the base count below 600 pt", () => {
    expect(gridColumns(2, 390)).toBe(2)
    expect(gridColumns(3, 599)).toBe(3)
    expect(gridColumns(4, 430)).toBe(4)
    expect(gridColumns(1, 1024)).toBe(1)
  })

  it("doubles it from 600 pt", () => {
    expect(gridColumns(2, 600)).toBe(4)
    expect(gridColumns(3, 852)).toBe(6)
    expect(gridColumns(4, 1024)).toBe(8)
  })
})

describe("chunkRows", () => {
  it("splits a list into rows of n, the last one may be shorter", () => {
    expect(chunkRows([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]])
    expect(chunkRows([], 3)).toEqual([])
  })

  it("treats a count below 1 as 1", () => {
    expect(chunkRows([1, 2], 0)).toEqual([[1], [2]])
  })
})

describe("gridCellSize", () => {
  it("fits the columns between the 16 pt gutters with 12 pt between them", () => {
    expect(gridCellSize(390, 2)).toBe(Math.floor((390 - 32 - 12) / 2))
    expect(gridCellSize(390, 3)).toBe(Math.floor((390 - 32 - 24) / 3))
    expect(gridCellSize(852, 8)).toBe(Math.floor((852 - 32 - 84) / 8))
  })

  it("is never below 1", () => {
    expect(gridCellSize(10, 4)).toBe(1)
  })
})
