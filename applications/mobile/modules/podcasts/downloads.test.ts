// LOFI-FORK: the podcasts section's downloads (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  applyChange,
  downloadFraction,
  downloadedCount,
  downloadLook,
  downloadsSummary,
  downloadMenuTitle,
  formatStorage,
  mapFromList,
  shouldDownloadOnPlay,
  skipAdsFor,
  sortDownloads,
  storageOf,
} from "./downloads"
import type { DownloadInfo } from "./index"

const info = (patch: Partial<DownloadInfo> & { episodeId: string }) =>
  ({ state: "queued", updatedAt: 1000, ...patch }) as DownloadInfo

describe("applyChange", () => {
  it("adds and replaces a download by episode", () => {
    const first = applyChange({}, info({ episodeId: "a" }))
    const second = applyChange(
      first,
      info({ episodeId: "a", state: "downloading", bytes: 5, expected: 10 }),
    )
    expect(Object.keys(second)).toEqual(["a"])
    expect(second["a"]?.state).toBe("downloading")
    expect(first["a"]?.state).toBe("queued")
  })

  it("drops a removed download and keeps the same map when there was none", () => {
    const map = mapFromList([
      info({ episodeId: "a" }),
      info({ episodeId: "b" }),
    ])
    expect(
      Object.keys(applyChange(map, { episodeId: "a", state: "none" })),
    ).toEqual(["b"])
    expect(applyChange(map, { episodeId: "zzz", state: "none" })).toBe(map)
  })
})

describe("downloadFraction", () => {
  it("is the share received while downloading", () => {
    expect(
      downloadFraction(
        info({
          episodeId: "a",
          state: "downloading",
          bytes: 25,
          expected: 100,
        }),
      ),
    ).toBe(0.25)
  })
  it("is null when the size is unknown, and 1 once downloaded", () => {
    expect(
      downloadFraction(
        info({ episodeId: "a", state: "downloading", bytes: 25 }),
      ),
    ).toBeNull()
    expect(
      downloadFraction(
        info({ episodeId: "a", state: "downloaded", bytes: 25 }),
      ),
    ).toBe(1)
    expect(downloadFraction(info({ episodeId: "a" }))).toBeNull()
  })
  it("stays between 0 and 1", () => {
    expect(
      downloadFraction(
        info({
          episodeId: "a",
          state: "downloading",
          bytes: 300,
          expected: 100,
        }),
      ),
    ).toBe(1)
  })
})

describe("downloadLook", () => {
  it("offers a download for an episode with none", () => {
    expect(downloadLook(undefined, "Ep 1")).toMatchObject({
      icon: "download",
      action: "download",
      status: "",
      label: "Download Ep 1",
    })
  })
  it("says waiting for a queued download and lets it be cancelled", () => {
    expect(downloadLook(info({ episodeId: "a" }), "Ep 1")).toMatchObject({
      icon: "waiting",
      action: "cancel",
      status: "Waiting to download",
    })
  })
  it("shows the percent while downloading", () => {
    const look = downloadLook(
      info({
        episodeId: "a",
        state: "downloading",
        bytes: 421,
        expected: 1000,
      }),
      "Ep 1",
    )
    expect(look).toMatchObject({
      icon: "progress",
      fraction: 0.421,
      action: "cancel",
      status: "Downloading 42%",
    })
    expect(look.label).toBe("Downloading Ep 1, 42 percent. Cancel the download")
  })
  it("still says downloading when the size is not known", () => {
    const look = downloadLook(
      info({ episodeId: "a", state: "downloading", bytes: 5 }),
      "Ep 1",
    )
    expect(look).toMatchObject({ fraction: null, status: "Downloading" })
  })
  it("shows a check mark and the size once downloaded, with a delete action", () => {
    expect(
      downloadLook(
        info({ episodeId: "a", state: "downloaded", bytes: 52_400_000 }),
        "Ep 1",
      ),
    ).toMatchObject({
      icon: "done",
      action: "delete",
      status: "52.4 MB",
      label: "Downloaded Ep 1. Delete the download",
    })
  })
  it("shows the reason for a failed download and lets it try again", () => {
    expect(
      downloadLook(
        info({
          episodeId: "a",
          state: "failed",
          reason: "Stopped, tap to try again",
        }),
        "Ep 1",
      ),
    ).toMatchObject({
      icon: "failed",
      action: "retry",
      status: "Stopped, tap to try again",
    })
  })
})

describe("formatStorage", () => {
  it("writes sizes the way the phone's settings do", () => {
    expect(formatStorage(0)).toBe("0 MB")
    expect(formatStorage(512)).toBe("512 bytes")
    expect(formatStorage(12_000)).toBe("12 KB")
    expect(formatStorage(340_000_000)).toBe("340 MB")
    expect(formatStorage(52_400_000)).toBe("52.4 MB")
    expect(formatStorage(1_200_000_000)).toBe("1.2 GB")
    expect(formatStorage(2_000_000_000)).toBe("2 GB")
  })
  it("copes with numbers that are not sizes", () => {
    expect(formatStorage(Number.NaN)).toBe("0 MB")
    expect(formatStorage(-5)).toBe("0 MB")
  })
})

describe("storage and the summary", () => {
  const map = mapFromList([
    info({ episodeId: "a", state: "downloaded", bytes: 600_000_000 }),
    info({ episodeId: "b", state: "downloaded", bytes: 600_000_000 }),
    info({ episodeId: "c", state: "downloading", bytes: 999, expected: 2000 }),
  ])
  it("counts only finished downloads' bytes", () => {
    expect(storageOf(map)).toBe(1_200_000_000)
  })
  it("reads as a count and a size", () => {
    expect(downloadsSummary(map)).toBe("3 episodes, 1.2 GB")
    expect(downloadsSummary(mapFromList([info({ episodeId: "a" })]))).toBe(
      "1 episode, 0 MB",
    )
    expect(downloadsSummary({})).toBe("No downloads")
  })
})

describe("sortDownloads", () => {
  it("puts the newest first, using the finish time for finished ones", () => {
    const sorted = sortDownloads([
      info({
        episodeId: "old",
        state: "downloaded",
        date: 1000,
        updatedAt: 9000,
      }),
      info({ episodeId: "moving", updatedAt: 5000 }),
      info({
        episodeId: "new",
        state: "downloaded",
        date: 7000,
        updatedAt: 7000,
      }),
    ])
    expect(sorted.map((d) => d.episodeId)).toEqual(["new", "moving", "old"])
  })
  it("keeps equal times in a steady order and leaves the input alone", () => {
    const input = [info({ episodeId: "b" }), info({ episodeId: "a" })]
    expect(sortDownloads(input).map((d) => d.episodeId)).toEqual(["a", "b"])
    expect(input.map((d) => d.episodeId)).toEqual(["b", "a"])
  })
})

describe("downloadMenuTitle", () => {
  it("names each action the way the episode menu says it", () => {
    expect(downloadMenuTitle("download")).toBe("Download")
    expect(downloadMenuTitle("retry")).toBe("Download again")
    expect(downloadMenuTitle("cancel")).toBe("Cancel download")
    expect(downloadMenuTitle("delete")).toBe("Remove download")
  })
})

describe("shouldDownloadOnPlay", () => {
  const stream = { id: "e1" }

  it("downloads a streamed episode when Skip ads is on and nothing is downloaded", () => {
    expect(shouldDownloadOnPlay(stream, undefined, true)).toBe(true)
  })
  it("downloads again one whose download failed", () => {
    expect(
      shouldDownloadOnPlay(
        stream,
        info({ episodeId: "e1", state: "failed" }),
        true,
      ),
    ).toBe(true)
  })
  it("leaves one that is queued, downloading or downloaded alone", () => {
    for (const state of ["queued", "downloading", "downloaded"] as const) {
      expect(
        shouldDownloadOnPlay(stream, info({ episodeId: "e1", state }), true),
      ).toBe(false)
    }
  })
  it("plays through its own download when the automatic one has not started", () => {
    const waiting = { episodeId: "e1", automatic: true }
    expect(
      shouldDownloadOnPlay(stream, info({ ...waiting, state: "queued" }), true),
    ).toBe(true)
    expect(
      shouldDownloadOnPlay(
        stream,
        info({ ...waiting, state: "downloading", bytes: 0 }),
        true,
      ),
    ).toBe(true)
    // Once bytes have arrived, or when the listener asked for it, it is left alone.
    expect(
      shouldDownloadOnPlay(
        stream,
        info({ ...waiting, state: "downloading", bytes: 5 }),
        true,
      ),
    ).toBe(false)
    expect(
      shouldDownloadOnPlay(
        stream,
        info({ episodeId: "e1", automatic: false, state: "queued" }),
        true,
      ),
    ).toBe(false)
  })
  it("does nothing when Skip ads is off", () => {
    expect(shouldDownloadOnPlay(stream, undefined, false)).toBe(false)
  })
  it("does nothing for an added file or a preview", () => {
    expect(shouldDownloadOnPlay({ id: "file-1" }, undefined, true)).toBe(false)
    expect(shouldDownloadOnPlay({ id: "preview:s:1" }, undefined, true)).toBe(
      false,
    )
  })
})

describe("skipAdsFor", () => {
  it("takes the show's own choice when it has one, else the main switch", () => {
    expect(skipAdsFor(true, false)).toBe(true)
    expect(skipAdsFor(false, true)).toBe(false)
    expect(skipAdsFor(null, true)).toBe(true)
    expect(skipAdsFor(undefined, false)).toBe(false)
  })
})

describe("downloadedCount", () => {
  it("counts finished and moving downloads, not failed ones", () => {
    const map = mapFromList([
      info({ episodeId: "a", state: "downloaded" }),
      info({ episodeId: "b", state: "downloading" }),
      info({ episodeId: "c", state: "queued" }),
      info({ episodeId: "d", state: "failed" }),
    ])
    expect(downloadedCount(map)).toBe(3)
    expect(downloadedCount({})).toBe(0)
  })
})
