// LOFI-FORK: the podcasts section's tests (see FORK.md).
import { describe, expect, it } from "vitest"

import { withAppleLists } from "./appleLists"

describe("withAppleLists", () => {
  it("keeps two read-change-write jobs from overwriting each other", async () => {
    let stored: string[] = []
    const add = (item: string) =>
      withAppleLists(async () => {
        const read = [...stored]
        await new Promise((resolve) => setTimeout(resolve, 5))
        stored = [...read, item]
      })
    await Promise.all([add("a"), add("b"), add("c")])
    expect(stored).toEqual(["a", "b", "c"])
  })

  it("carries on after a job fails", async () => {
    await expect(
      withAppleLists(() => Promise.reject(new Error("no"))),
    ).rejects.toThrow("no")
    await expect(withAppleLists(() => Promise.resolve(1))).resolves.toBe(1)
  })
})
