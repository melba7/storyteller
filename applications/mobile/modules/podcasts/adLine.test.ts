// LOFI-FORK: the podcasts section's ads (see FORK.md).
import { describe, expect, it } from "vitest"

import { adsToShow, playerAdLine } from "./adLine"
import type { AdsInfo, DownloadInfo, TranscriptInfo } from "./index"

const download = (
  state: DownloadInfo["state"],
  extra: Partial<DownloadInfo> = {},
): DownloadInfo => ({ episodeId: "e", state, updatedAt: 0, ...extra })
const transcript = (
  state: TranscriptInfo["state"],
  extra: Partial<TranscriptInfo> = {},
): TranscriptInfo => ({ episodeId: "e", state, ...extra })
const ads = (
  state: AdsInfo["state"],
  extra: Partial<AdsInfo> = {},
): AdsInfo => ({
  episodeId: "e",
  state,
  ...extra,
})

const base = { episodeId: "e", skipAds: true }

describe("playerAdLine", () => {
  it("says nothing while Skip ads is off, or for an added file", () => {
    expect(
      playerAdLine({
        ...base,
        skipAds: false,
        download: download("downloaded"),
      }),
    ).toBe("")
    expect(
      playerAdLine({ ...base, episodeId: "file-1", download: undefined }),
    ).toBe("")
  })

  it("says it streams without skipping when there is no download", () => {
    expect(playerAdLine({ ...base, download: undefined })).toBe(
      "Streaming without ad skipping",
    )
    expect(playerAdLine({ ...base, download: download("failed") })).toBe(
      "Streaming without ad skipping",
    )
  })

  it("says it streams without skipping when the player plays the plain address", () => {
    const line = (download: DownloadInfo | undefined, adsInfo?: AdsInfo) =>
      playerAdLine({
        ...base,
        streamsPlain: true,
        download,
        transcript: transcript("done"),
        ads: adsInfo,
      })
    // Nothing on the phone to skip with next time.
    expect(line(undefined)).toBe("Streaming without ad skipping")
    expect(line(download("failed"))).toBe("Streaming without ad skipping")
    // A download exists or is running: the next play will skip, and the ads found are not
    // claimed as skipped now.
    const next = "Streaming without ad skipping. Next play will skip ads."
    expect(line(download("downloading"))).toBe(next)
    expect(line(download("downloaded"), ads("found", { count: 3 }))).toBe(next)
    expect(line(download("downloaded"), ads("noAds"))).toBe(next)
  })

  it("says it is checking the start while Play waits for the first look", () => {
    const checking = "Checking the start for ads"
    // The download is still arriving then, which would otherwise read "Getting ready".
    expect(
      playerAdLine({
        ...base,
        checkingStart: true,
        download: download("downloading"),
      }),
    ).toBe(checking)
    expect(
      playerAdLine({ ...base, checkingStart: true, download: undefined }),
    ).toBe(checking)
    expect(
      playerAdLine({
        ...base,
        checkingStart: false,
        download: download("downloading"),
      }),
    ).toBe("Getting ready to find ads")
  })

  it("says nothing about the start while Skip ads is off or for an added file", () => {
    expect(
      playerAdLine({
        ...base,
        skipAds: false,
        checkingStart: true,
        download: download("downloading"),
      }),
    ).toBe("")
    expect(
      playerAdLine({
        ...base,
        episodeId: "file-1",
        checkingStart: true,
        download: undefined,
      }),
    ).toBe("")
  })

  it("keeps the other lines when the player plays the file", () => {
    expect(
      playerAdLine({
        ...base,
        streamsPlain: false,
        download: download("downloaded"),
        transcript: transcript("done"),
        ads: ads("found", { count: 3 }),
      }),
    ).toBe("3 ads found")
  })

  it("says nothing about streaming while Skip ads is off or for an added file", () => {
    expect(
      playerAdLine({
        ...base,
        skipAds: false,
        streamsPlain: true,
        download: undefined,
      }),
    ).toBe("")
    expect(
      playerAdLine({
        ...base,
        episodeId: "file-1",
        streamsPlain: true,
        download: undefined,
      }),
    ).toBe("")
  })

  it("is getting ready while the file arrives or nothing has started", () => {
    const ready = "Getting ready to find ads"
    expect(playerAdLine({ ...base, download: download("queued") })).toBe(ready)
    expect(playerAdLine({ ...base, download: download("downloading") })).toBe(
      ready,
    )
    expect(playerAdLine({ ...base, download: download("downloaded") })).toBe(
      ready,
    )
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("waiting"),
      }),
    ).toBe(ready)
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("done"),
        ads: ads("waiting"),
      }),
    ).toBe(ready)
  })

  it("finds ads while transcribing, with the percent", () => {
    const line = (info: TranscriptInfo, adsInfo?: AdsInfo) =>
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: info,
        ads: adsInfo,
      })
    expect(line(transcript("transcribing", { percent: 40.6 }))).toBe(
      "Finding ads, 40% transcribed",
    )
    expect(line(transcript("transcribing"))).toBe("Finding ads")
    expect(
      line(transcript("transcribing", { percent: 40 }), ads("finding")),
    ).toBe("Finding ads, 40% transcribed")
  })

  it("finds ads after the transcript is done", () => {
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("done"),
        ads: ads("finding", { percent: 55 }),
      }),
    ).toBe("Finding ads, 55%")
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("done"),
        ads: ads("finding"),
      }),
    ).toBe("Finding ads")
  })

  it("says a prepared episode is prepared by the Mac, before its transcript is done", () => {
    const line = (adsInfo: AdsInfo, transcriptInfo?: TranscriptInfo) =>
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcriptInfo,
        ads: adsInfo,
      })
    expect(line(ads("found", { count: 2, prepared: true }))).toBe(
      "Your Mac's marks",
    )
    expect(
      line(ads("noAds", { prepared: true }), transcript("transcribing")),
    ).toBe("Your Mac's marks")
    expect(
      adsToShow(
        true,
        transcript("waiting"),
        ads("found", { count: 2, prepared: true }),
      ),
    ).toEqual(ads("found", { count: 2, prepared: true }))
  })

  it("shows the Mac's marks line only for an episode that has them", () => {
    const line = (adsInfo: AdsInfo | undefined, state: DownloadInfo["state"]) =>
      playerAdLine({
        ...base,
        download: download(state),
        transcript: transcript("done"),
        ads: adsInfo,
      })
    expect(line(ads("found", { count: 2, macMarks: true }), "downloaded")).toBe(
      "Your Mac's marks",
    )
    // A stream whose episode has the marks says so instead of "without ad skipping".
    expect(
      playerAdLine({
        ...base,
        download: undefined,
        ads: ads("waiting", { macMarks: true }),
      }),
    ).toBe("Your Mac's marks")
    // Nothing new without the marks.
    expect(line(ads("found", { count: 2 }), "downloaded")).toBe("2 ads found")
    expect(playerAdLine({ ...base, download: undefined })).toBe(
      "Streaming without ad skipping",
    )
  })

  it("shows the Mac's marks on a stream when the player says its skips come from them", () => {
    const marks = "Your Mac's marks"
    // No ads info for a stream (it is not in the table of downloads): the player's flag says it.
    expect(playerAdLine({ ...base, download: undefined, macMarks: true })).toBe(
      marks,
    )
    expect(
      playerAdLine({
        ...base,
        download: download("downloading"),
        macMarks: true,
      }),
    ).toBe(marks)
    // The start check still comes first, and a file on the phone says what its ads say.
    expect(
      playerAdLine({
        ...base,
        download: undefined,
        macMarks: true,
        checkingStart: true,
      }),
    ).toBe("Checking the start for ads")
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("done"),
        ads: ads("found", { count: 2 }),
        macMarks: true,
      }),
    ).toBe("2 ads found")
    expect(
      playerAdLine({ ...base, download: undefined, macMarks: false }),
    ).toBe("Streaming without ad skipping")
  })

  it("counts the ads found, and says when there are none", () => {
    const line = (adsInfo: AdsInfo) =>
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("done"),
        ads: adsInfo,
      })
    expect(line(ads("found", { count: 3 }))).toBe("3 ads found")
    expect(line(ads("found", { count: 1 }))).toBe("1 ad found")
    expect(line(ads("noAds"))).toBe("No ads found")
  })

  it("gives the reason ads can't be found, even before the transcript is done", () => {
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("transcribing", { percent: 10 }),
        ads: ads("unavailable", { reason: "Apple Intelligence is off" }),
      }),
    ).toBe("Ads can't be found: Apple Intelligence is off")
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        ads: ads("unavailable"),
      }),
    ).toBe("Ads can't be found")
  })

  it("a failure of this episode's search is one short line", () => {
    const reason =
      "Finding ads stopped: The model couldn't finish: A part of the transcript was too long."
    for (const transcriptInfo of [undefined, transcript("done")]) {
      const line = playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcriptInfo,
        ads: ads("unavailable", { reason }),
      })
      expect(line).toBe("Ad check paused. Trying again soon")
      expect(line.length).toBeLessThanOrEqual(40)
      expect(line).not.toContain("can't be found")
      // It does not repeat the reason, or any part of it.
      expect(line).not.toContain("Finding ads stopped")
      expect(line).not.toContain("model")
    }
    // The same wording whatever words follow the colon.
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        ads: ads("unavailable", {
          reason: "Finding ads stopped: The model refused to read a part.",
        }),
      }),
    ).toBe("Ad check paused. Trying again soon")
  })

  it("keeps 'Ads can't be found' for the reasons that belong to the phone", () => {
    for (const reason of [
      "Apple Intelligence is off",
      "The model is downloading",
      "This iPhone can't run Apple Intelligence",
      "Needs iOS 26",
      "Apple Intelligence is not available",
    ]) {
      expect(
        playerAdLine({
          ...base,
          download: download("downloaded"),
          transcript: transcript("done"),
          ads: ads("unavailable", { reason }),
        }),
      ).toBe(`Ads can't be found: ${reason}`)
    }
    // Any other reason that is not a failed search keeps its old words as well.
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        ads: ads("unavailable", { reason: "The transcript could not be read" }),
      }),
    ).toBe("Ads can't be found: The transcript could not be read")
  })

  it("says what was found, not a failure, when ads were found before it", () => {
    // Swift reports the ads found so far as "found" even while a failed run waits to be tried
    // again; the line then counts them.
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("done"),
        ads: ads("found", { count: 2 }),
      }),
    ).toBe("2 ads found")
  })

  it("gives the transcript's reason when it can't be made", () => {
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("unsupported", { reason: "Needs iOS 26" }),
      }),
    ).toBe("Ads can't be found: Needs iOS 26")
    expect(
      playerAdLine({
        ...base,
        download: download("downloaded"),
        transcript: transcript("failed"),
      }),
    ).toBe("Ads can't be found: Transcribing failed")
  })
})

describe("adsToShow", () => {
  it("shows nothing before the audio is on the phone", () => {
    expect(adsToShow(false, undefined, ads("unavailable"))).toBeUndefined()
  })

  it("shows the reason and the results before the transcript is done", () => {
    const busy = transcript("transcribing", { percent: 5 })
    const reason = ads("unavailable", { reason: "Apple Intelligence is off" })
    expect(adsToShow(true, busy, reason)).toBe(reason)
    expect(adsToShow(true, busy, ads("found", { count: 1 }))).toEqual(
      ads("found", { count: 1 }),
    )
  })

  it("keeps quiet about waiting while the transcript is not done", () => {
    expect(
      adsToShow(true, transcript("transcribing"), ads("waiting")),
    ).toBeUndefined()
    expect(adsToShow(true, transcript("done"), ads("waiting"))).toEqual(
      ads("waiting"),
    )
  })
})
