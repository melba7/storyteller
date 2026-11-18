// LOFI-FORK: the podcasts section's player (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import {
  CLOSED_GATE,
  type Gate,
  type GateEffect,
  type GateEvent,
  SETTLE_TIMEOUT_MS,
  STALE_AFTER_MS,
  step,
} from "./playerGate"
import { type RequestedPage } from "./playerPageRequest"

type Plain = Exclude<GateEvent["type"], "open">

function open(at: number, page?: RequestedPage): GateEvent {
  return { type: "open", at, page: page ?? null }
}

function ev(type: Plain, at: number): GateEvent {
  return { type, at }
}

/** Feeds the events in order and returns every effect, page and the last gate. */
function run(events: readonly GateEvent[], from: Gate = CLOSED_GATE) {
  let gate = from
  const effects: GateEffect[] = []
  const pages: (RequestedPage | null)[] = []
  for (const event of events) {
    const result = step(gate, event)
    gate = result.gate
    effects.push(result.effect)
    pages.push(result.page)
  }
  return { gate, effects, pages }
}

describe("the player gate: one step at a time", () => {
  it("four open requests in a row push once", () => {
    const { effects, gate } = run([open(0), open(10), open(20), open(30)])
    expect(effects).toEqual(["push", null, null, null])
    expect(gate.state).toBe("opening")
  })

  it("four open requests push once even when the player shows in between", () => {
    const { effects } = run([
      open(0),
      open(100),
      ev("shown", 200),
      open(300),
      open(400),
    ])
    expect(effects).toEqual(["push", null, null, null, null])
  })

  it("an open while closing pushes nothing and pushes once after gone", () => {
    const { effects, gate } = run([
      open(0),
      ev("shown", 100),
      ev("leaving", 2000),
      open(2010),
      open(2020),
      open(2030),
      ev("gone", 2300),
      ev("gone", 2310),
    ])
    expect(effects).toEqual([
      "push",
      null,
      null,
      null,
      null,
      null,
      "push",
      null,
    ])
    expect(gate.state).toBe("closed")
  })

  it("an open while closing by our own back also waits for gone", () => {
    const { effects } = run([
      open(0),
      ev("shown", 100),
      ev("close", 2000),
      open(2100),
      ev("gone", 2200),
    ])
    expect(effects).toEqual(["push", null, "back", null, "push"])
  })

  it("two close events go back once", () => {
    const { effects, gate } = run([
      open(0),
      ev("shown", 100),
      ev("close", 2000),
      ev("close", 2010),
    ])
    expect(effects).toEqual(["push", null, "back", null])
    expect(gate.state).toBe("closing")
  })

  it("a close with the gate not showing open still lets the listener leave once", () => {
    const { effects } = run([ev("close", 0), ev("close", 10)])
    expect(effects).toEqual(["back", null])
  })

  it("a timeout while opening returns to closed, and the next open pushes", () => {
    const first = run([open(0), ev("timeout", SETTLE_TIMEOUT_MS)])
    expect(first.effects).toEqual(["push", null])
    expect(first.gate.state).toBe("closed")
    const second = run([open(SETTLE_TIMEOUT_MS + 10)], first.gate)
    expect(second.effects).toEqual(["push"])
  })

  it("a timeout while closing returns to closed", () => {
    const { gate, effects } = run([
      open(0),
      ev("shown", 100),
      ev("close", 2000),
      ev("timeout", 2000 + SETTLE_TIMEOUT_MS),
    ])
    expect(effects).toEqual(["push", null, "back", null])
    expect(gate.state).toBe("closed")
  })

  it("a timeout while closing with a remembered tap pushes it", () => {
    const { effects, pages, gate } = run([
      open(0),
      ev("shown", 100),
      ev("leaving", 2000),
      open(2100, "transcript"),
      ev("timeout", 2000 + SETTLE_TIMEOUT_MS),
    ])
    expect(effects).toEqual(["push", null, null, null, "push"])
    expect(pages[4]).toBe("transcript")
    expect(gate.state).toBe("opening")
  })

  it("an open more than 700 ms after shown goes back once and pushes once after gone", () => {
    const { effects, gate } = run([
      open(0),
      ev("shown", 100),
      open(100 + STALE_AFTER_MS + 1),
      open(100 + STALE_AFTER_MS + 20),
      ev("gone", 1000),
      ev("gone", 1010),
    ])
    expect(effects).toEqual(["push", null, "back", null, "push", null])
    // The second gone is a stray: a gone while opening means the pushed player went away again.
    expect(gate.state).toBe("closed")
  })

  it("an open at exactly 700 ms after shown is a double tap, not a stale state", () => {
    const { effects } = run([
      open(0),
      ev("shown", 100),
      open(100 + STALE_AFTER_MS),
    ])
    expect(effects).toEqual(["push", null, null])
  })

  it("a page asked for with a dropped open is not kept anywhere", () => {
    const { effects, pages, gate } = run([
      open(0),
      open(5, "transcript"),
      ev("shown", 100),
      open(150, "notes"),
    ])
    expect(effects).toEqual(["push", null, null, null])
    expect(pages).toEqual([null, null, null, null])
    expect(gate.queued).toBeNull()
    // Closing and going away must not bring either page back.
    const after = run(
      [ev("close", 1000), ev("gone", 1100), ev("gone", 1200)],
      gate,
    )
    expect(after.effects).toEqual(["back", null, null])
    expect(after.pages).toEqual([null, null, null])
  })

  it("a page comes back only with the push it belongs to", () => {
    const { effects, pages } = run([
      open(0, "chapters"),
      ev("shown", 100),
      ev("leaving", 2000),
      open(2100, "transcript"),
      ev("gone", 2300),
    ])
    expect(effects).toEqual(["push", null, null, null, "push"])
    expect(pages).toEqual(["chapters", null, null, null, "transcript"])
  })

  it("a sheet that stays after a cancelled swipe forgets the tap made meanwhile", () => {
    const { effects, gate } = run([
      open(0),
      ev("shown", 100),
      ev("leaving", 2000),
      open(2050, "transcript"),
      ev("stayed", 2100),
      ev("gone", 3000),
    ])
    expect(effects).toEqual(["push", null, null, null, null, null])
    expect(gate.state).toBe("closed")
  })

  it("leaving, open, gone pushes once", () => {
    const { effects } = run(
      [ev("leaving", 2000), open(2100), ev("gone", 2400)],
      { state: "open", since: 100, queued: null },
    )
    expect(effects).toEqual([null, null, "push"])
  })

  it("an open then gone before shown ends closed, and the next open pushes again", () => {
    const { effects, gate } = run([open(0), ev("gone", 50), open(100)])
    expect(effects).toEqual(["push", null, "push"])
    expect(gate.state).toBe("opening")
  })

  it("a stray leaving or stayed changes nothing unless a swipe was under way", () => {
    const { effects, gate } = run([ev("leaving", 0), ev("stayed", 10)])
    expect(effects).toEqual([null, null])
    expect(gate).toEqual(CLOSED_GATE)
    // Pushed but not shown yet: a late "stayed" must not make the gate open.
    const opening = run([open(0), ev("leaving", 5), ev("stayed", 10)])
    expect(opening.gate).toEqual({ state: "opening", since: 0, queued: null })
    // Showing: a "stayed" changes nothing, and does not refresh the time of the stale rule.
    const showing = run([open(0), ev("shown", 50), ev("stayed", 400)])
    expect(showing.gate).toEqual({ state: "open", since: 50, queued: null })
  })

  it("a close we asked for is not undone by a late stayed", () => {
    // Without a swipe under way there is no "closing" to cancel: our own back stays closing.
    const { gate } = run([open(0), ev("shown", 50), ev("close", 100)])
    expect(gate.state).toBe("closing")
  })

  it("shown always means open and drops a remembered tap", () => {
    const closing = run([
      open(0),
      ev("shown", 50),
      ev("leaving", 100),
      open(120),
    ]).gate
    expect(closing.queued).not.toBeNull()
    const shown = step(closing, ev("shown", 200))
    expect(shown.gate).toEqual({ state: "open", since: 200, queued: null })
    expect(step(CLOSED_GATE, ev("shown", 5)).gate.state).toBe("open")
  })

  it("a timeout in every state", () => {
    const at = 10_000
    const timeout = ev("timeout", at)
    expect(step({ ...CLOSED_GATE }, timeout).gate.state).toBe("closed")
    expect(
      step({ state: "open", since: 0, queued: null }, timeout).gate.state,
    ).toBe("open")
    expect(
      step({ state: "opening", since: 0, queued: null }, timeout),
    ).toMatchObject({ gate: { state: "closed" }, effect: null })
    expect(
      step({ state: "closing", since: 0, queued: null }, timeout),
    ).toMatchObject({ gate: { state: "closed" }, effect: null })
    expect(
      step({ state: "closing", since: 0, queued: { page: null } }, timeout),
    ).toMatchObject({ gate: { state: "opening" }, effect: "push" })
  })

  it("a state that rests in opening or closing is always left by the timeout", () => {
    const resting: Gate[] = [
      { state: "opening", since: 0, queued: null },
      { state: "closing", since: 0, queued: null },
      { state: "closing", since: 0, queued: { page: "notes" } },
    ]
    for (const gate of resting) {
      const first = step(gate, ev("timeout", SETTLE_TIMEOUT_MS))
      // A remembered tap is pushed, which rests in opening: one more timeout frees it.
      const second = step(first.gate, ev("timeout", 2 * SETTLE_TIMEOUT_MS))
      expect(["opening", "closing"]).not.toContain(second.gate.state)
      expect(second.effect).toBeNull()
    }
  })

  it("takes the time from the event and never reads a clock", () => {
    const date = vi.spyOn(Date, "now")
    const perf = vi.spyOn(performance, "now")
    run([
      open(0),
      ev("shown", 10),
      open(5000),
      ev("gone", 5100),
      ev("close", 5200),
      ev("timeout", 9000),
    ])
    expect(date).not.toHaveBeenCalled()
    expect(perf).not.toHaveBeenCalled()
    date.mockRestore()
    perf.mockRestore()
  })

  it("does not change the gate it was given", () => {
    const gate: Gate = { state: "closing", since: 5, queued: null }
    const frozen = Object.freeze({ ...gate })
    expect(() => step(frozen, open(10, "notes"))).not.toThrow()
    expect(frozen).toEqual(gate)
  })

  it("holds its rules for every order of up to five events", () => {
    const kinds: GateEvent["type"][] = [
      "open",
      "close",
      "shown",
      "gone",
      "leaving",
      "stayed",
      "timeout",
    ]
    // Times 400 ms apart, so some opens are on each side of the 700 ms stale limit.
    function walk(gate: Gate, depth: number, index: number) {
      if (depth === 0) return
      for (const type of kinds) {
        const at = index * 400
        const event: GateEvent =
          type === "open" ? open(at, "transcript") : ev(type, at)
        const result = step(gate, event)
        if (result.effect === "push") {
          expect(["closed", "closing"]).toContain(gate.state)
          expect(result.gate.state).toBe("opening")
        }
        if (result.effect === "back") {
          expect(gate.state).not.toBe("closing")
          expect(result.gate.state).toBe("closing")
        }
        if (result.page !== null) expect(result.effect).toBe("push")
        if (result.gate.queued !== null) {
          expect(result.gate.state).toBe("closing")
        }
        // The timeout frees a resting state in at most two more steps.
        if (["opening", "closing"].includes(result.gate.state)) {
          const one = step(result.gate, ev("timeout", at + SETTLE_TIMEOUT_MS))
          const two = step(one.gate, ev("timeout", at + 2 * SETTLE_TIMEOUT_MS))
          expect(["opening", "closing"]).not.toContain(two.gate.state)
        }
        walk(result.gate, depth - 1, index + 1)
      }
    }
    walk(CLOSED_GATE, 5, 1)
  })
})
