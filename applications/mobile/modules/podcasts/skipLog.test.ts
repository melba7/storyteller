// LOFI-FORK: the podcasts section's skip log (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import { sendSkipLog } from "./skipLog"

describe("sendSkipLog", () => {
  it("opens the share sheet with the copy the phone made", async () => {
    const share = vi.fn(async () => {})
    const outcome = await sendSkipLog({
      copyLog: async () => "file:///caches/skip-log.jsonl",
      canShare: async () => true,
      share,
    })
    expect(outcome).toBe("shared")
    expect(share).toHaveBeenCalledOnce()
    expect(share).toHaveBeenCalledWith("file:///caches/skip-log.jsonl")
  })

  it("says the log is empty when nothing was skipped yet", async () => {
    const share = vi.fn(async () => {})
    const outcome = await sendSkipLog({
      copyLog: async () => null,
      canShare: async () => true,
      share,
    })
    expect(outcome).toBe("empty")
    expect(share).not.toHaveBeenCalled()
  })

  it("says so, and shares nothing, when this device cannot share", async () => {
    const share = vi.fn(async () => {})
    await expect(
      sendSkipLog({
        copyLog: async () => "file:///caches/skip-log.jsonl",
        canShare: async () => false,
        share,
      }),
    ).rejects.toThrow("Sharing isn't available on this device.")
    expect(share).not.toHaveBeenCalled()
  })

  it("lets a failure of the share sheet through", async () => {
    await expect(
      sendSkipLog({
        copyLog: async () => "file:///caches/skip-log.jsonl",
        canShare: async () => true,
        share: async () => {
          throw new Error("No room")
        },
      }),
    ).rejects.toThrow("No room")
  })
})
