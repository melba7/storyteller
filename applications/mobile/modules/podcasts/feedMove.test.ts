// LOFI-FORK: the podcasts section's tests (see FORK.md).
import { describe, expect, it } from "vitest"

import { movedFeedUrl } from "./feedMove"

const show = { id: "a", feedUrl: "https://old.example.com/feed.xml" }
const other = { id: "b", feedUrl: "https://other.example.com/feed.xml" }

describe("movedFeedUrl", () => {
  it("returns the new address, normalised", () => {
    expect(
      movedFeedUrl(show, " https://NEW.example.com/feed.xml#x ", [show, other]),
    ).toBe("https://new.example.com/feed.xml")
  })

  it("reads a missing, empty, non-web or malformed value as no move", () => {
    for (const value of [
      undefined,
      null,
      42,
      "",
      "  ",
      "feed://new.example.com/f.xml",
      "ftp://new.example.com/f.xml",
      "not a link",
      "https://nodot/feed",
    ]) {
      expect(movedFeedUrl(show, value, [show])).toBeNull()
    }
  })

  it("is no move when it is the same feed under another spelling", () => {
    expect(
      movedFeedUrl(show, "http://www.old.example.com/feed.xml", [show]),
    ).toBeNull()
  })

  it("is no move when another show already has that address", () => {
    expect(
      movedFeedUrl(show, "http://www.other.example.com/feed.xml", [
        show,
        other,
      ]),
    ).toBeNull()
  })
})
