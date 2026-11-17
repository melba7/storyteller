// LOFI-FORK: the podcasts section's downloads (see FORK.md).
import { describe, expect, it } from "vitest"

import type { DownloadInfo } from "./index"
import {
  WAIT_LIMIT_MS,
  WIFI_GRACE_MS,
  announcedPercent,
  waitDecision,
  waitPercent,
} from "./playWait"

const info = (patch: Partial<DownloadInfo>): DownloadInfo =>
  ({ episodeId: "e1", state: "downloading", ...patch }) as DownloadInfo

const decide = (
  patch: Partial<Parameters<typeof waitDecision>[0]> = {},
): ReturnType<typeof waitDecision> =>
  waitDecision({
    download: info({ bytes: 10, expected: 100 }),
    elapsedMs: 5_000,
    wifiOnly: false,
    streamAsked: false,
    ...patch,
  })

describe("waitDecision", () => {
  it("keeps waiting while the download makes progress", () => {
    expect(decide()).toBe("wait")
  })
  it("keeps waiting for a download that just began", () => {
    expect(
      decide({ download: info({ state: "queued" }), elapsedMs: 500 }),
    ).toBe("wait")
  })
  it("plays the file when the download is done", () => {
    expect(decide({ download: info({ state: "downloaded" }) })).toBe("play")
  })
  it("streams when the download failed", () => {
    expect(decide({ download: info({ state: "failed" }) })).toBe("stream")
  })
  it("streams when the download is gone (cancelled)", () => {
    expect(decide({ download: undefined })).toBe("stream")
  })
  it("streams when it waits for Wi-Fi with nothing received", () => {
    expect(
      decide({
        download: info({ state: "queued" }),
        wifiOnly: true,
        elapsedMs: WIFI_GRACE_MS,
      }),
    ).toBe("stream")
    expect(
      decide({
        download: info({ state: "queued" }),
        wifiOnly: true,
        elapsedMs: WIFI_GRACE_MS - 1,
      }),
    ).toBe("wait")
  })
  it("does not call a moving download a wait for Wi-Fi", () => {
    expect(decide({ wifiOnly: true, elapsedMs: WIFI_GRACE_MS * 2 })).toBe(
      "wait",
    )
  })
  it("queued without Wi-Fi only is not a wait for Wi-Fi", () => {
    expect(
      decide({ download: info({ state: "queued" }), elapsedMs: 20_000 }),
    ).toBe("wait")
  })
  it("streams after the time limit", () => {
    expect(decide({ elapsedMs: WAIT_LIMIT_MS })).toBe("stream")
    expect(decide({ elapsedMs: WAIT_LIMIT_MS - 1 })).toBe("wait")
  })
  it("streams when the listener asked, even with the file done", () => {
    expect(decide({ streamAsked: true })).toBe("stream")
    expect(
      decide({ streamAsked: true, download: info({ state: "downloaded" }) }),
    ).toBe("stream")
  })
  it("is 60 seconds", () => {
    expect(WAIT_LIMIT_MS).toBe(60_000)
  })
})

describe("waitPercent", () => {
  it("is the share downloaded, or null when not known", () => {
    expect(waitPercent(info({ bytes: 25, expected: 100 }))).toBe(25)
    expect(waitPercent(info({ state: "queued" }))).toBeNull()
    expect(waitPercent(undefined)).toBeNull()
    expect(waitPercent(info({ state: "downloaded" }))).toBe(100)
  })
})

describe("announcedPercent", () => {
  it("changes only every ten percent", () => {
    expect(announcedPercent(0)).toBe(0)
    expect(announcedPercent(9)).toBe(0)
    expect(announcedPercent(10)).toBe(10)
    expect(announcedPercent(57)).toBe(50)
    expect(announcedPercent(100)).toBe(100)
    expect(announcedPercent(null)).toBeNull()
  })
})
