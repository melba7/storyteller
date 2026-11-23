// LOFI-FORK: the podcasts section's ads (see FORK.md).
import { beforeEach, describe, expect, it, vi } from "vitest"

const answerAdQuestion =
  vi.fn<(episodeId: string, start: number, isAd: boolean) => Promise<boolean>>()

vi.mock("./index", () => ({ Podcasts: { answerAdQuestion } }))

describe("answerAdQuestion", () => {
  beforeEach(() => {
    answerAdQuestion.mockReset()
  })

  it("hands the episode, the question's start and the answer to the native module", async () => {
    answerAdQuestion.mockResolvedValue(true)
    const { answerAdQuestion: answer } = await import("./adsNative")
    expect(await answer("e1", 600.25, true)).toBe(true)
    expect(answerAdQuestion).toHaveBeenCalledWith("e1", 600.25, true)
    await answer("e1", 600.25, false)
    expect(answerAdQuestion).toHaveBeenLastCalledWith("e1", 600.25, false)
  })

  it("says whether an open question took the answer", async () => {
    answerAdQuestion.mockResolvedValue(false)
    const { answerAdQuestion: answer } = await import("./adsNative")
    expect(await answer("e1", 600, true)).toBe(false)
  })
})
