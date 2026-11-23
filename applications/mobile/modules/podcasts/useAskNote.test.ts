// LOFI-FORK: the podcasts section's question note (see FORK.md).
//
// The hook is called as a plain function, with React's two hooks replaced by what they come to
// when nothing changes between calls, the native module by a list of its listeners and the
// player by a view that the test moves.
import { beforeEach, describe, expect, it, vi } from "vitest"

type Listener = (event: unknown) => void

const listeners = new Map<string, Listener>()
let view = { episode: { id: "e1" } as { id: string } | null, position: 0 }
const answerAdQuestion =
  vi.fn<(episodeId: string, start: number, isAd: boolean) => Promise<boolean>>()

vi.mock("react", () => ({
  useSyncExternalStore: (
    subscribe: (listener: () => void) => () => void,
    get: () => unknown,
  ) => {
    subscribe(() => {})
    return get()
  },
  useEffect: (effect: () => void) => {
    effect()
  },
}))
vi.mock("@/modules/podcasts/index", () => ({
  Podcasts: {
    addListener: (name: string, listener: Listener) => {
      listeners.set(name, listener)
      return { remove() {} }
    },
  },
}))
vi.mock("@/modules/podcasts/playerInstance", () => ({
  usePlayerValue: (select: (view: unknown) => unknown) => select(view),
}))
vi.mock("@/modules/podcasts/adsNative", () => ({ answerAdQuestion }))

const asked = { episodeId: "e1", start: 600, end: 660, kind: "ad" }

async function load() {
  vi.resetModules()
  listeners.clear()
  return await import("@/podcasts/useAskNote")
}

beforeEach(() => {
  view = { episode: { id: "e1" }, position: 610 }
  answerAdQuestion.mockReset()
  answerAdQuestion.mockResolvedValue(true)
})

describe("useAskNote", () => {
  it("shows nothing until the phone asks", async () => {
    const { useAskNote } = await load()
    expect(useAskNote()).toBeNull()
  })

  it("shows the question when the player sends onAdAsk", async () => {
    const { useAskNote } = await load()
    useAskNote()
    listeners.get("onAdAsk")?.(asked)
    expect(useAskNote()).toEqual(asked)
  })

  it("goes when the playhead is past the end of the stretch, and stays gone", async () => {
    const { useAskNote } = await load()
    useAskNote()
    listeners.get("onAdAsk")?.(asked)
    view.position = 660
    expect(useAskNote()).toBeNull()
    view.position = 630
    expect(useAskNote()).toBeNull()
  })

  it("goes when another episode is loaded, and stays gone", async () => {
    const { useAskNote } = await load()
    useAskNote()
    listeners.get("onAdAsk")?.(asked)
    view.episode = { id: "e2" }
    expect(useAskNote()).toBeNull()
    view.episode = { id: "e1" }
    expect(useAskNote()).toBeNull()
  })

  it("goes when nothing is loaded", async () => {
    const { useAskNote } = await load()
    useAskNote()
    listeners.get("onAdAsk")?.(asked)
    view.episode = null
    expect(useAskNote()).toBeNull()
  })

  it("goes when the Skip ad button skipped the stretch", async () => {
    const { useAskNote } = await load()
    useAskNote()
    listeners.get("onAdAsk")?.(asked)
    listeners.get("onAdSkipped")?.({
      episodeId: "e1",
      start: 600,
      end: 660,
      length: 60,
    })
    expect(useAskNote()).toBeNull()
  })

  it("answers Skip with yes for the question's episode and start, and goes", async () => {
    const { useAskNote, pressAskAnswer } = await load()
    useAskNote()
    listeners.get("onAdAsk")?.(asked)
    pressAskAnswer(true)
    expect(answerAdQuestion).toHaveBeenCalledTimes(1)
    expect(answerAdQuestion).toHaveBeenCalledWith("e1", 600, true)
    expect(useAskNote()).toBeNull()
  })

  it("answers Not an ad with no, and goes", async () => {
    const { useAskNote, pressAskAnswer } = await load()
    useAskNote()
    listeners.get("onAdAsk")?.(asked)
    pressAskAnswer(false)
    expect(answerAdQuestion).toHaveBeenCalledWith("e1", 600, false)
    expect(useAskNote()).toBeNull()
  })
})
