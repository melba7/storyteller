// LOFI-FORK: the podcasts section's error messages (see FORK.md).
import { describe, expect, it } from "vitest"

import { readableError } from "./nativeError"

describe("readableError", () => {
  it("takes the cause out of the module's wrapper text", () => {
    const error = new Error(
      "Call to function 'Podcasts.fetchFeed' has been rejected.\n→ Caused by: This link isn't a podcast feed.",
    )
    expect(readableError(error)).toBe("This link isn't a podcast feed.")
  })

  it("keeps a plain message", () => {
    expect(readableError(new Error("Podcasts need the iOS app."))).toBe(
      "Podcasts need the iOS app.",
    )
    expect(readableError("odd")).toBe("odd")
  })

  it("has something to say for an empty message", () => {
    expect(readableError(new Error(""))).toBe("Something went wrong.")
  })
})
