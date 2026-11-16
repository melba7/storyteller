// LOFI-FORK: the podcasts section's change notice (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import {
  libraryVersion,
  notifyLibraryChanged,
  onLibraryChanged,
} from "./changes"

describe("library changes", () => {
  it("tells listeners and counts the changes", () => {
    const listener = vi.fn()
    const stop = onLibraryChanged(listener)
    const before = libraryVersion()
    notifyLibraryChanged()
    expect(listener).toHaveBeenCalledTimes(1)
    expect(libraryVersion()).toBe(before + 1)
    stop()
    notifyLibraryChanged()
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it("lets a listener stop itself while being told", () => {
    const calls: string[] = []
    const stopFirst = onLibraryChanged(() => {
      calls.push("first")
      stopFirst()
    })
    const stopSecond = onLibraryChanged(() => calls.push("second"))
    notifyLibraryChanged()
    notifyLibraryChanged()
    expect(calls).toEqual(["first", "second", "second"])
    stopSecond()
  })
})
