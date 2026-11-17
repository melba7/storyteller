// LOFI-FORK: the podcasts section's transcripts (see FORK.md).
import { describe, expect, it } from "vitest"

import type { TranscriptInfo } from "./index"
import {
  applyTranscriptChange,
  transcriptMapFromList,
  transcriptStatus,
  withTranscript,
} from "./transcripts"

const info = (
  state: TranscriptInfo["state"],
  extra: Partial<TranscriptInfo> = {},
): TranscriptInfo => ({ episodeId: "e1", state, ...extra })

describe("transcriptStatus", () => {
  it("says where the transcript is", () => {
    expect(transcriptStatus(undefined)).toBe("")
    expect(transcriptStatus(info("waiting"))).toBe("Waiting to transcribe")
    expect(transcriptStatus(info("transcribing", { percent: 40 }))).toBe(
      "Transcribing 40%",
    )
    expect(transcriptStatus(info("transcribing"))).toBe("Transcribing")
    expect(transcriptStatus(info("done"))).toBe("Transcript ready")
  })

  it("gives the reason when there is no transcript", () => {
    expect(
      transcriptStatus(info("unsupported", { reason: "Needs iOS 26" })),
    ).toBe("Needs iOS 26")
    expect(transcriptStatus(info("unsupported"))).toBe("Language not supported")
    expect(transcriptStatus(info("failed", { reason: "Out of space" }))).toBe(
      "Out of space",
    )
    expect(transcriptStatus(info("failed"))).toBe("Transcribing failed")
  })

  it("keeps the percent in range", () => {
    expect(transcriptStatus(info("transcribing", { percent: 140 }))).toBe(
      "Transcribing 100%",
    )
    expect(transcriptStatus(info("transcribing", { percent: 42.9 }))).toBe(
      "Transcribing 42%",
    )
  })
})

describe("withTranscript", () => {
  it("puts the transcript after the download's line", () => {
    expect(withTranscript("340 MB", info("done"))).toBe(
      "340 MB · Transcript ready",
    )
    expect(withTranscript("", info("done"))).toBe("Transcript ready")
    expect(withTranscript("340 MB", undefined)).toBe("340 MB")
  })
})

describe("changes from Swift", () => {
  it("adds, replaces and removes", () => {
    let map = transcriptMapFromList([info("waiting")])
    map = applyTranscriptChange(map, info("transcribing", { percent: 5 }))
    expect(map["e1"]?.percent).toBe(5)
    map = applyTranscriptChange(map, { episodeId: "e1", state: "none" })
    expect(map).toEqual({})
    expect(applyTranscriptChange(map, { episodeId: "x", state: "none" })).toBe(
      map,
    )
  })
})
