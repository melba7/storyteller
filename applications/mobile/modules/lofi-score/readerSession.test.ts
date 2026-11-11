// LOFI-FORK: tests for when the music while reading starts and stops (see
// FORK.md).
import { describe, expect, it } from "vitest"

import { ReaderSession, readerMoveMs, readerSettleMs } from "./readerSession"

/** Timers that run only when the test says so. */
function manualTimers() {
  const pending = new Map<number, () => void>()
  let next = 1
  return {
    later(action: () => void) {
      const handle = next++
      pending.set(handle, action)
      return handle
    },
    cancel(handle: unknown) {
      pending.delete(handle as number)
    },
    runAll() {
      const actions = [...pending.values()]
      pending.clear()
      actions.forEach((action) => {
        action()
      })
    },
  }
}

function session() {
  const timers = manualTimers()
  let stops = 0
  const reader = new ReaderSession(() => {
    stops += 1
  }, timers)
  return { reader, timers, stops: () => stops }
}

describe("ReaderSession", () => {
  it("does not take the page the book opens at as a page turn", () => {
    const { reader } = session()
    reader.shown("book", 1_000)
    expect(reader.isPageTurn("book", 1_000 + 1_200)).toBe(false)
    expect(reader.isPageTurn("book", 1_000 + readerSettleMs - 1)).toBe(false)
  })

  it("takes later page reports as page turns", () => {
    const { reader } = session()
    reader.shown("book", 1_000)
    expect(reader.isPageTurn("book", 1_000 + readerSettleMs)).toBe(true)
    expect(reader.isPageTurn("book", 1_000 + 60_000)).toBe(true)
  })

  it("waits again when the app comes back to the book", () => {
    const { reader, timers, stops } = session()
    reader.shown("book", 0)
    reader.hidden(30_000)
    timers.runAll()
    expect(stops()).toBe(1)
    reader.shown("book", 90_000)
    expect(reader.isPageTurn("book", 91_000)).toBe(false)
    expect(reader.isPageTurn("book", 90_000 + readerSettleMs)).toBe(true)
  })

  it("waits again even when the stop was held up while the app was away", () => {
    const { reader, stops } = session()
    reader.shown("book", 0)
    reader.hidden(30_000)
    reader.shown("book", 90_000)
    expect(stops()).toBe(1)
    expect(reader.isPageTurn("book", 91_000)).toBe(false)
  })

  it("keeps the music when the toolbar only moves", () => {
    const { reader, timers, stops } = session()
    reader.shown("book", 0)
    reader.hidden(40_000)
    reader.shown("book", 40_000 + readerMoveMs - 1)
    timers.runAll()
    expect(stops()).toBe(0)
    expect(reader.isPageTurn("book", 41_000)).toBe(true)
  })

  it("stops the last book's music when another book opens right after", () => {
    const { reader, timers, stops } = session()
    reader.shown("first", 0)
    reader.hidden(40_000)
    reader.shown("second", 40_000)
    timers.runAll()
    expect(stops()).toBe(1)
    expect(reader.isPageTurn("second", 41_000)).toBe(false)
    expect(reader.isPageTurn("first", 60_000)).toBe(false)
    expect(reader.isPageTurn("second", 40_000 + readerSettleMs)).toBe(true)
  })

  it("stops the music once when the book closes", () => {
    const { reader, timers, stops } = session()
    reader.shown("book", 0)
    reader.hidden(10_000)
    reader.hidden(10_001)
    timers.runAll()
    expect(stops()).toBe(1)
  })

  it("follows every page report when the reader never said it opened", () => {
    const { reader } = session()
    expect(reader.isPageTurn("book", 0)).toBe(true)
  })
})
