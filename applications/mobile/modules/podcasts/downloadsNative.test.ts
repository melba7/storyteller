// LOFI-FORK: the podcasts section's downloads (see FORK.md).
import { beforeEach, describe, expect, it, vi } from "vitest"

const download = vi.fn<(...args: unknown[]) => Promise<void>>()
const lookAheadNative = vi.fn<() => Promise<void>>()

vi.mock("./index", () => ({
  Podcasts: { download, lookAhead: lookAheadNative },
}))

describe("startDownload", () => {
  beforeEach(() => {
    download.mockReset()
    download.mockResolvedValue(undefined)
  })

  it("hands the episode's show to the native module", async () => {
    const { startDownload } = await import("./downloadsNative")
    await startDownload(
      "e1",
      "https://a.test/e1.mp3",
      "audio/mpeg",
      true,
      "en",
      "s1",
    )
    expect(download).toHaveBeenCalledWith(
      "e1",
      "https://a.test/e1.mp3",
      "audio/mpeg",
      true,
      "en",
      "s1",
    )
  })

  it("sends null for the language and the show when none is given", async () => {
    const { startDownload } = await import("./downloadsNative")
    await startDownload("e1", "https://a.test/e1.mp3", "audio/mpeg")
    expect(download).toHaveBeenCalledWith(
      "e1",
      "https://a.test/e1.mp3",
      "audio/mpeg",
      false,
      null,
      null,
    )
  })
})

describe("lookAhead", () => {
  beforeEach(() => {
    lookAheadNative.mockReset()
    lookAheadNative.mockResolvedValue(undefined)
  })

  it("asks the native module to look at Up Next now", async () => {
    const { lookAhead } = await import("./downloadsNative")
    await lookAhead()
    expect(lookAheadNative).toHaveBeenCalledTimes(1)
  })
})
