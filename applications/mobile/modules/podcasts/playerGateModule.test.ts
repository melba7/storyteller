// LOFI-FORK: the podcasts section's player (see FORK.md).
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { SETTLE_TIMEOUT_MS, STALE_AFTER_MS } from "./playerGate"

describe("the module's one gate", () => {
  type Gates = typeof import("./playerGate")
  type Requests = typeof import("./playerPageRequest")

  function fakeRouter(canGoBack = true) {
    return {
      push: vi.fn<(href: "/podcasts/player") => void>(),
      back: vi.fn<() => void>(),
      canGoBack: vi.fn(() => canGoBack),
      replace: vi.fn<(href: "/podcasts") => void>(),
    }
  }

  let gates: Gates
  let requests: Requests

  beforeEach(async () => {
    vi.useFakeTimers()
    vi.resetModules()
    gates = await import("./playerGate")
    requests = await import("./playerPageRequest")
  })

  afterEach(() => {
    vi.clearAllTimers()
    vi.useRealTimers()
  })

  it("two mini player copies share one gate", () => {
    const copyA = fakeRouter()
    const copyB = fakeRouter()
    gates.openPlayer(copyA)
    gates.openPlayer(copyB)
    gates.openPlayer(copyA)
    gates.openPlayer(copyB)
    expect(copyA.push).toHaveBeenCalledTimes(1)
    expect(copyA.push).toHaveBeenCalledWith("/podcasts/player")
    expect(copyB.push).not.toHaveBeenCalled()
  })

  it("four quick taps open once, and after one swipe down the next tap opens again", () => {
    const router = fakeRouter()
    for (let tap = 0; tap < 4; tap++) {
      gates.openPlayer(router)
      vi.advanceTimersByTime(100)
    }
    gates.playerShown()
    gates.playerLeaving()
    gates.playerGone()
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(2)
    expect(router.back).not.toHaveBeenCalled()
  })

  it("a tap while the sheet slides away opens it once the sheet is gone", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    gates.playerShown()
    vi.advanceTimersByTime(5000)
    gates.playerLeaving()
    gates.openPlayer(router, "transcript")
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(1)
    // Nothing is asked of the player until the push really happens.
    expect(requests.takePlayerPageRequest()).toBeNull()
    gates.playerGone()
    expect(router.push).toHaveBeenCalledTimes(2)
    // The last tap, a plain one, replaced the page that was asked for before it.
    expect(requests.takePlayerPageRequest()).toBeNull()
  })

  it("a remembered page is asked for only when its push happens", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    gates.playerShown()
    gates.playerLeaving()
    gates.openPlayer(router, "transcript")
    expect(requests.takePlayerPageRequest()).toBeNull()
    gates.playerGone()
    expect(router.push).toHaveBeenCalledTimes(2)
    expect(requests.takePlayerPageRequest()).toBe("transcript")
  })

  it("a dropped request leaves no page request behind", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    gates.openPlayer(router, "transcript")
    expect(router.push).toHaveBeenCalledTimes(1)
    expect(requests.takePlayerPageRequest()).toBeNull()
  })

  it("a plain open does not show a page asked for by an open that never mounted", () => {
    const router = fakeRouter()
    gates.openPlayer(router, "transcript")
    expect(router.push).toHaveBeenCalledTimes(1)
    // The player never mounts: the timeout frees the gate and drops the request.
    vi.advanceTimersByTime(SETTLE_TIMEOUT_MS)
    expect(requests.takePlayerPageRequest()).toBeNull()
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(2)
    expect(requests.takePlayerPageRequest()).toBeNull()
  })

  it("a plain open does not inherit a page left behind by something else", () => {
    const router = fakeRouter()
    requests.requestPlayerPage("notes")
    router.push.mockImplementation(() => {
      expect(requests.takePlayerPageRequest()).toBeNull()
    })
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(1)
  })

  it("asks for the page just before the push, so the player finds it when it mounts", () => {
    const router = fakeRouter()
    router.push.mockImplementation(() => {
      expect(requests.takePlayerPageRequest()).toBe("chapters")
    })
    gates.openPlayer(router, "chapters")
    expect(router.push).toHaveBeenCalledTimes(1)
  })

  it("runs a timer only while opening or closing and clears it on shown and gone", () => {
    const router = fakeRouter()
    expect(vi.getTimerCount()).toBe(0)
    gates.openPlayer(router)
    expect(vi.getTimerCount()).toBe(1)
    gates.openPlayer(router)
    expect(vi.getTimerCount()).toBe(1)
    gates.playerShown()
    expect(vi.getTimerCount()).toBe(0)
    gates.closePlayer(router)
    expect(vi.getTimerCount()).toBe(1)
    gates.playerGone()
    expect(vi.getTimerCount()).toBe(0)
  })

  it("frees an opening that never showed, after 1.5 seconds", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    vi.advanceTimersByTime(SETTLE_TIMEOUT_MS - 1)
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(1)
    expect(vi.getTimerCount()).toBe(0)
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(2)
  })

  it("frees a closing whose gone never came, after 1.5 seconds", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    gates.playerShown()
    gates.closePlayer(router)
    gates.closePlayer(router)
    expect(router.back).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(SETTLE_TIMEOUT_MS)
    expect(vi.getTimerCount()).toBe(0)
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(2)
  })

  it("pushes a remembered tap with the router it came with when the timeout frees it", () => {
    const first = fakeRouter()
    const second = fakeRouter()
    gates.openPlayer(first)
    gates.playerShown()
    gates.playerLeaving()
    gates.openPlayer(second)
    vi.advanceTimersByTime(SETTLE_TIMEOUT_MS)
    expect(second.push).toHaveBeenCalledTimes(1)
    expect(first.push).toHaveBeenCalledTimes(1)
    // That push rests in opening, which the next timeout frees.
    expect(vi.getTimerCount()).toBe(1)
    vi.advanceTimersByTime(SETTLE_TIMEOUT_MS)
    expect(vi.getTimerCount()).toBe(0)
  })

  it("an open when the sheet cannot be covering the mini player goes back once, then pushes once", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    gates.playerShown()
    vi.advanceTimersByTime(STALE_AFTER_MS)
    gates.openPlayer(router)
    expect(router.back).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)
    gates.openPlayer(router)
    gates.openPlayer(router)
    expect(router.back).toHaveBeenCalledTimes(1)
    expect(router.push).toHaveBeenCalledTimes(1)
    gates.playerGone()
    expect(router.push).toHaveBeenCalledTimes(2)
  })

  it("closes once, and replaces the section when there is nothing to go back to", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    gates.playerShown()
    gates.closePlayer(router)
    gates.closePlayer(router)
    expect(router.back).toHaveBeenCalledTimes(1)
    expect(router.replace).not.toHaveBeenCalled()

    const lonely = fakeRouter(false)
    gates.playerGone()
    gates.openPlayer(lonely)
    gates.playerShown()
    gates.closePlayer(lonely)
    expect(lonely.back).not.toHaveBeenCalled()
    expect(lonely.replace).toHaveBeenCalledWith("/podcasts")
  })

  it("a router that throws does not break the tap, and the timeout frees the gate", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    const router = fakeRouter()
    router.push.mockImplementationOnce(() => {
      throw new Error("not mounted yet")
    })
    expect(() => gates.openPlayer(router)).not.toThrow()
    expect(warn).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(SETTLE_TIMEOUT_MS)
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(2)
    warn.mockRestore()
  })

  it("keeps the first deadline when more taps arrive while opening", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    for (let tap = 0; tap < 10; tap++) {
      vi.advanceTimersByTime(SETTLE_TIMEOUT_MS / 10 - 1)
      gates.openPlayer(router)
    }
    vi.advanceTimersByTime(10)
    expect(vi.getTimerCount()).toBe(0)
  })

  it("waits a plain 1.5 seconds even if the clock jumps back", () => {
    const router = fakeRouter()
    gates.openPlayer(router)
    vi.setSystemTime(Date.now() - 3_600_000)
    gates.openPlayer(router)
    vi.advanceTimersByTime(SETTLE_TIMEOUT_MS)
    expect(vi.getTimerCount()).toBe(0)
  })

  it("a push that shows at once leaves no timer behind", () => {
    const router = fakeRouter()
    router.push.mockImplementation(() => gates.playerShown())
    gates.openPlayer(router)
    gates.openPlayer(router)
    expect(router.push).toHaveBeenCalledTimes(1)
    expect(vi.getTimerCount()).toBe(0)
  })
})
