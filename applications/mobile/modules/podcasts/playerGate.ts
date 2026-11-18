// LOFI-FORK: the podcasts section's player (see FORK.md).
//
// The one door to the player page. The player is a modal sheet, and every tap on the mini player
// used to push another copy of it, so three taps meant three sheets and three swipes (and a tap
// during the slide away could leave the native modal stuck for good). The gate lets exactly one
// open request through, remembers a tap made while the sheet is sliding away and opens once the
// sheet is gone, and goes back only once on a double tap of the close control.
//
// `step` is a pure function: the time comes in with each event, so the tests need no clock. The
// functions at the bottom keep the module's one gate (both copies of the mini player share it),
// run the effects on the router and keep one timer, which runs exactly while the gate is in a
// state that must not last (opening or closing) and frees it when the sheet's own events never
// came.

import {
  type RequestedPage,
  requestPlayerPage,
  takePlayerPageRequest,
} from "./playerPageRequest"

/**
 * closed: no sheet. opening: pushed, the player has not shown yet. open: the sheet is showing.
 * closing: it is going away (a swipe has started, or we went back) and its `gone` is awaited.
 */
export type GateState = "closed" | "opening" | "open" | "closing"

export type Gate = {
  state: GateState
  /** When the gate entered this state (milliseconds, from the event's time). */
  since: number
  /** An open request made while closing, pushed once the sheet is gone. */
  queued: { page: RequestedPage | null } | null
}

/**
 * open: someone wants the player (a page may be asked for). close: the listener closed it.
 * shown and gone: the player screen mounted and unmounted. leaving and stayed: the sheet began
 * to go away (a swipe started) and the swipe was cancelled so the sheet stayed. timeout: the
 * timer for a state that must not last has run out.
 */
export type GateEvent =
  | { type: "open"; at: number; page?: RequestedPage | null }
  | {
      type: "close" | "shown" | "gone" | "leaving" | "stayed" | "timeout"
      at: number
    }

export type GateEffect = "push" | "back" | null

/** The next gate and what to do. `page` is the page to ask for, and only goes with a push. */
export type GateStep = {
  gate: Gate
  effect: GateEffect
  page: RequestedPage | null
}

export const CLOSED_GATE: Gate = { state: "closed", since: 0, queued: null }

/**
 * An open request this long after the player showed cannot come from a tap on the mini player
 * under a sheet that covers it, so the gate's "open" is stale and the sheet is not really there.
 */
export const STALE_AFTER_MS = 700

/** How long opening or closing may last before the timeout frees the gate. */
export const SETTLE_TIMEOUT_MS = 1500

function stay(gate: Gate): GateStep {
  return { gate, effect: null, page: null }
}

function enter(state: GateState, at: number): GateStep {
  return { gate: { state, since: at, queued: null }, effect: null, page: null }
}

function push(at: number, page: RequestedPage | null): GateStep {
  return {
    gate: { state: "opening", since: at, queued: null },
    effect: "push",
    page,
  }
}

function back(at: number, queued: Gate["queued"]): GateStep {
  return {
    gate: { state: "closing", since: at, queued },
    effect: "back",
    page: null,
  }
}

function onOpen(gate: Gate, at: number, page: RequestedPage | null): GateStep {
  switch (gate.state) {
    case "closed":
      return push(at, page)
    case "opening":
      return stay(gate)
    case "open":
      // The mini player is under the sheet, so a tap now means the sheet is not there.
      return at - gate.since > STALE_AFTER_MS ? back(at, { page }) : stay(gate)
    case "closing":
      return { gate: { ...gate, queued: { page } }, effect: null, page: null }
  }
}

/** What happens to the gate for one event, and the effect to run. Pure. */
export function step(gate: Gate, event: GateEvent): GateStep {
  const at = event.at
  switch (event.type) {
    case "open":
      return onOpen(gate, at, event.page ?? null)
    case "close":
      // Only the player itself asks to close, so even a gate that thinks it is closed lets the
      // listener out.
      return gate.state === "closing" ? stay(gate) : back(at, null)
    case "shown":
      return enter("open", at)
    case "gone":
      if (gate.state === "closed") return stay(gate)
      if (gate.state === "closing" && gate.queued) {
        return push(at, gate.queued.page)
      }
      return enter("closed", at)
    case "leaving":
      return gate.state === "open" ? enter("closing", at) : stay(gate)
    case "stayed":
      return gate.state === "closing" ? enter("open", at) : stay(gate)
    case "timeout":
      if (gate.state === "opening") return enter("closed", at)
      if (gate.state === "closing") {
        return gate.queued ? push(at, gate.queued.page) : enter("closed", at)
      }
      return stay(gate)
  }
}

/** What the gate needs from expo-router's router. */
export type PlayerRouter = {
  push: (href: "/podcasts/player") => void
  back: () => void
  canGoBack: () => boolean
  replace: (href: "/podcasts") => void
}

let gate: Gate = CLOSED_GATE
let timer: ReturnType<typeof setTimeout> | null = null
// The state and entry time the running timer was started for.
let timed: { state: GateState; since: number } | null = null
// The router of the latest open request: a remembered tap is pushed later, from `gone` or the
// timer, which have no router of their own.
let latestRouter: PlayerRouter | null = null

/**
 * One timer, running exactly while the gate is opening or closing. A request that changes
 * nothing (a dropped open) leaves it running, so hammering the mini player cannot push the end
 * of the wait further away. The wait is a plain length of time, so a change of the clock cannot
 * stretch it.
 */
function keepTimer() {
  const resting = gate.state === "opening" || gate.state === "closing"
  if (
    resting &&
    timed?.state === gate.state &&
    timed.since === gate.since &&
    timer !== null
  ) {
    return
  }
  if (timer !== null) clearTimeout(timer)
  timer = null
  timed = null
  if (!resting) return
  timed = { state: gate.state, since: gate.since }
  timer = setTimeout(() => {
    timer = null
    timed = null
    send({ type: "timeout", at: Date.now() }, null)
  }, SETTLE_TIMEOUT_MS)
}

/** Does what the gate decided. A router that throws leaves the gate to the timer. */
function perform(
  router: PlayerRouter,
  effect: GateEffect,
  page: RequestedPage | null,
) {
  try {
    if (effect === "push") {
      // Drop any leftover request first, so a plain open never shows an old page.
      takePlayerPageRequest()
      if (page) requestPlayerPage(page)
      router.push("/podcasts/player")
    } else if (effect === "back") {
      if (router.canGoBack()) router.back()
      else router.replace("/podcasts")
    }
  } catch (cause) {
    console.warn("Couldn't open or close the player", cause)
  }
}

function send(event: GateEvent, router: PlayerRouter | null) {
  const before = gate.state
  const result = step(gate, event)
  // The gate and the timer are settled before the effect runs, because the router may call
  // back into the gate at once.
  gate = result.gate
  keepTimer()
  // An opening that ends closed never showed the player, so the page asked for is forgotten.
  if (before === "opening" && gate.state === "closed") takePlayerPageRequest()
  const target = router ?? latestRouter
  if (target && result.effect) perform(target, result.effect, result.page)
}

/** Opens the player (the mini player, the episode menu), once however often it is asked. */
export function openPlayer(router: PlayerRouter, page?: RequestedPage) {
  latestRouter = router
  send({ type: "open", at: Date.now(), page: page ?? null }, router)
}

/** Closes the player (the close control), once however often it is asked. */
export function closePlayer(router: PlayerRouter) {
  send({ type: "close", at: Date.now() }, router)
}

/** The player screen mounted. */
export function playerShown() {
  send({ type: "shown", at: Date.now() }, null)
}

/** The player screen unmounted. */
export function playerGone() {
  send({ type: "gone", at: Date.now() }, null)
}

/** The sheet began to slide away (a swipe started). */
export function playerLeaving() {
  send({ type: "leaving", at: Date.now() }, null)
}

/** The sheet stayed: the swipe that had started was cancelled. */
export function playerStayed() {
  send({ type: "stayed", at: Date.now() }, null)
}
