// LOFI-FORK: the podcasts section's player (see FORK.md).
import { describe, expect, it } from "vitest"

import { requestPlayerPage, takePlayerPageRequest } from "./playerPageRequest"

describe("the player page request", () => {
  it("hands over a request once", () => {
    expect(takePlayerPageRequest()).toBeNull()
    requestPlayerPage("transcript")
    expect(takePlayerPageRequest()).toBe("transcript")
    expect(takePlayerPageRequest()).toBeNull()
  })

  it("keeps only the last request", () => {
    requestPlayerPage("notes")
    requestPlayerPage("chapters")
    expect(takePlayerPageRequest()).toBe("chapters")
  })
})
