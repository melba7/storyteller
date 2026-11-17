// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type AppleSyncStatus,
  describeStatus,
  problemFor,
  retryDelay,
} from "./appleStatus"

const base: AppleSyncStatus = {
  reading: false,
  readAt: null,
  shows: null,
  followed: 0,
  problem: null,
}
const NOW = Date.UTC(2030, 0, 10, 12, 0, 0)

describe("problemFor", () => {
  it("says in plain words why there is nothing to read", () => {
    expect(problemFor({ status: "notLinked" })).toBe("Folder not linked")
    expect(problemFor({ status: "folderGone" })).toBe(
      "The linked folder can't be opened",
    )
    expect(problemFor({ status: "missing" })).toBe(
      "No Apple Podcasts file in the folder yet",
    )
    expect(problemFor({ status: "notDownloaded" })).toBe(
      "File not downloaded yet",
    )
    expect(problemFor({ status: "unreadable", message: "Too large." })).toBe(
      "Too large.",
    )
    expect(problemFor({ status: "found", text: "{}" })).toBeNull()
  })
})

describe("retryDelay", () => {
  it("waits a few short times for iCloud, then stops", () => {
    expect(retryDelay(0)).toBe(20_000)
    expect(retryDelay(1)).toBe(30_000)
    expect(retryDelay(2)).toBe(60_000)
    expect(retryDelay(3)).toBeNull()
  })
})

describe("describeStatus", () => {
  it("is empty before the first read", () => {
    expect(describeStatus(base, NOW)).toBe("Not read yet")
  })
  it("says it is reading", () => {
    expect(describeStatus({ ...base, reading: true }, NOW)).toBe("Reading…")
  })
  it("gives the shows found and how many it followed", () => {
    expect(
      describeStatus(
        { ...base, readAt: NOW - 5 * 60_000, shows: 64, followed: 3 },
        NOW,
      ),
    ).toBe("64 shows found, 3 followed now, read 5 min ago")
    expect(
      describeStatus(
        { ...base, readAt: NOW - 30_000, shows: 1, followed: 0 },
        NOW,
      ),
    ).toBe("1 show found, read just now")
  })
  it("gives the problem and when the file was last read", () => {
    expect(
      describeStatus({ ...base, problem: "File not downloaded yet" }, NOW),
    ).toBe("File not downloaded yet")
    expect(
      describeStatus(
        {
          ...base,
          problem: "File not downloaded yet",
          readAt: NOW - 3 * 3_600_000,
          shows: 5,
        },
        NOW,
      ),
    ).toBe("File not downloaded yet (last read 3 h ago)")
  })
})
