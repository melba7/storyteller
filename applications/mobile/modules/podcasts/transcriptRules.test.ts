// LOFI-FORK: the podcasts section's transcripts (see FORK.md).
import { describe, expect, it } from "vitest"

import type { TranscriptInfo } from "./index"
import {
  TRANSCRIPT_CACHE_MS,
  chooseTranscript,
  deviceChoice,
  deviceSource,
  partialFooter,
  transcriptCacheFresh,
  transcriptSource,
} from "./transcriptChoice"
import type { TranscriptLine } from "./transcriptFormats"
import {
  deviceLines,
  foldText,
  lineAt,
  lineTimeLabel,
  searchLines,
  speakerChanges,
  stepMatch,
} from "./transcriptLines"

describe("chooseTranscript", () => {
  const t = (type: string, url = `https://x.test/t.${type}`) => ({ url, type })

  it("prefers JSON, then WebVTT, then SRT, then HTML", () => {
    const all = [
      t("text/html"),
      t("application/x-subrip"),
      t("text/vtt"),
      t("application/json"),
    ]
    expect(chooseTranscript(all)?.type).toBe("application/json")
    expect(chooseTranscript(all.slice(0, 3))?.type).toBe("text/vtt")
    expect(chooseTranscript(all.slice(0, 2))?.type).toBe("application/x-subrip")
    expect(chooseTranscript(all.slice(0, 1))?.type).toBe("text/html")
  })

  it("skips plain text and unknown types", () => {
    expect(chooseTranscript([t("text/plain"), t("application/pdf")])).toBeNull()
    expect(chooseTranscript([t("text/plain"), t("text/vtt")])?.type).toBe(
      "text/vtt",
    )
  })

  it("takes the first of a format, in feed order", () => {
    const first = t("text/vtt", "https://x.test/en.vtt")
    expect(
      chooseTranscript([first, t("text/vtt", "https://x.test/de.vtt")])?.url,
    ).toBe(first.url)
  })

  it("copes with none", () => {
    expect(chooseTranscript([])).toBeNull()
    expect(chooseTranscript(undefined)).toBeNull()
    expect(chooseTranscript([{ url: "", type: "text/vtt" }])).toBeNull()
  })
})

describe("transcriptSource", () => {
  const device = (
    state: TranscriptInfo["state"],
    extra = {},
  ): TranscriptInfo => ({
    episodeId: "e",
    state,
    ...extra,
  })

  it("uses the feed's transcript when there is one", () => {
    expect(
      transcriptSource({
        feedUrl: "https://x.test/t.vtt",
        feedType: "text/vtt",
        device: device("done"),
      }),
    ).toEqual({ kind: "feed", url: "https://x.test/t.vtt", type: "text/vtt" })
  })

  it("then the one made on the phone", () => {
    expect(
      transcriptSource({
        feedUrl: null,
        feedType: null,
        device: device("done"),
      }),
    ).toEqual({ kind: "device" })
  })

  it("then says why there is none", () => {
    const none = (info: TranscriptInfo | undefined) =>
      deviceSource(info) as { kind: "none"; reason: string }
    expect(none(undefined).reason).toBe(
      "No transcript yet. Download the episode to make one.",
    )
    expect(none(device("transcribing", { percent: 40 })).reason).toBe(
      "Transcribing 40%",
    )
    expect(none(device("waiting")).reason).toBe("Waiting to transcribe")
    expect(none(device("unsupported", { reason: "Needs iOS 26" })).reason).toBe(
      "Needs iOS 26",
    )
  })
})

describe("the cache", () => {
  it("keeps a transcript for a week", () => {
    expect(transcriptCacheFresh(1000, 1000 + TRANSCRIPT_CACHE_MS - 1)).toBe(
      true,
    )
    expect(transcriptCacheFresh(1000, 1000 + TRANSCRIPT_CACHE_MS)).toBe(false)
    expect(transcriptCacheFresh(5000, 1000)).toBe(false)
  })
})

const lines: TranscriptLine[] = [
  { start: 2, end: 4, speaker: "Ada", text: "Welcome to the café." },
  { start: 4, end: 6, speaker: "Ada", text: "Today: tea." },
  { start: 10, end: 12, speaker: "Ben", text: "Thanks, Ada. TEA is great." },
]

describe("lineAt", () => {
  it("finds the line that contains the time", () => {
    expect(lineAt(lines, 2)).toBe(0)
    expect(lineAt(lines, 3.9)).toBe(0)
    expect(lineAt(lines, 4)).toBe(1)
    expect(lineAt(lines, 11)).toBe(2)
    expect(lineAt(lines, 99999)).toBe(2)
  })

  it("holds the line before in a gap and the first line before the start", () => {
    expect(lineAt(lines, 7)).toBe(1)
    expect(lineAt(lines, 0)).toBe(0)
    expect(lineAt(lines, -5)).toBe(0)
  })

  it("has no line for no lines", () => {
    expect(lineAt([], 3)).toBe(-1)
  })

  it("is fast and right in a long transcript", () => {
    const many = Array.from({ length: 5000 }, (_, i) => ({
      start: i * 3,
      end: i * 3 + 2,
      text: `line ${i}`,
    }))
    expect(lineAt(many, 3 * 4321 + 1)).toBe(4321)
    expect(lineAt(many, 3 * 4321 + 2.5)).toBe(4321)
  })
})

describe("searchLines", () => {
  it("ignores case and accents", () => {
    expect(searchLines(lines, "CAFE")).toEqual([0])
    expect(searchLines(lines, "tea")).toEqual([1, 2])
    expect(foldText("Crème Brûlée")).toBe("creme brulee")
  })

  it("needs every word of the query", () => {
    expect(searchLines(lines, "tea great")).toEqual([2])
    expect(searchLines(lines, "tea zebra")).toEqual([])
  })

  it("finds nothing for an empty query", () => {
    expect(searchLines(lines, "")).toEqual([])
    expect(searchLines(lines, "   ")).toEqual([])
  })
})

describe("stepMatch", () => {
  it("goes round the matches", () => {
    expect(stepMatch([1, 4, 9], null, 1)).toBe(1)
    expect(stepMatch([1, 4, 9], 1, 1)).toBe(4)
    expect(stepMatch([1, 4, 9], 9, 1)).toBe(1)
    expect(stepMatch([1, 4, 9], 1, -1)).toBe(9)
    expect(stepMatch([1, 4, 9], null, -1)).toBe(9)
    expect(stepMatch([], null, 1)).toBeNull()
  })
})

describe("labels", () => {
  it("writes the time of a line", () => {
    expect(lineTimeLabel(5)).toBe("0:05")
    expect(lineTimeLabel(245.9)).toBe("4:05")
    expect(lineTimeLabel(3723)).toBe("1:02:03")
  })

  it("shows a speaker when it changes", () => {
    expect([0, 1, 2].map((i) => speakerChanges(lines, i))).toEqual([
      true,
      false,
      true,
    ])
    expect(speakerChanges([{ start: 0, end: 1, text: "x" }], 0)).toBe(false)
  })
})

describe("deviceLines", () => {
  it("reads the lines of the phone's transcript", () => {
    const json = JSON.stringify({
      version: 1,
      words: [],
      lines: [
        { start: 0.5, end: 2, text: "Hello there." },
        { start: 2, end: 3, text: "" },
        { start: "x", end: 3, text: "bad" },
      ],
    })
    expect(deviceLines(json)).toEqual([
      { start: 0.5, end: 2, text: "Hello there." },
    ])
  })

  it("is null for anything else", () => {
    expect(deviceLines("nope")).toBeNull()
    expect(deviceLines("{}")).toBeNull()
    expect(deviceLines('{"lines": []}')).toBeNull()
    expect(deviceLines("null")).toBeNull()
  })
})

describe("deviceChoice", () => {
  const info = (
    state: TranscriptInfo["state"],
    extra = {},
  ): TranscriptInfo => ({ episodeId: "e", state, ...extra })

  it("is finished when the transcript is done", () => {
    expect(deviceChoice(info("done"))).toEqual({ kind: "finished" })
  })
  it("is partial while transcribing, with the percent and the words for no lines yet", () => {
    expect(deviceChoice(info("transcribing", { percent: 40.7 }))).toEqual({
      kind: "partial",
      percent: 40,
      empty: "Transcribing, 40%. The first lines appear in a minute or so.",
    })
  })
  it("is partial while waiting, since a paused episode keeps its saved lines", () => {
    expect(deviceChoice(info("waiting"))).toEqual({
      kind: "partial",
      percent: null,
      empty: "Waiting to transcribe",
    })
  })
  it("says why there is none otherwise", () => {
    expect(deviceChoice(info("failed", { reason: "Out of space" }))).toEqual({
      kind: "none",
      reason: "Out of space",
    })
    expect(deviceChoice(undefined)).toEqual({
      kind: "none",
      reason: "No transcript yet. Download the episode to make one.",
    })
  })
})

describe("partialFooter", () => {
  it("names the percent", () => {
    expect(partialFooter(40)).toBe(
      "Transcribing, 40%. More lines appear as it goes.",
    )
    expect(partialFooter(null)).toBe(
      "Transcribing. More lines appear as it goes.",
    )
  })
})

describe("deviceLines of a transcript still being made", () => {
  it("reads the lines built from the words so far", () => {
    const json = JSON.stringify({
      version: 1,
      words: [],
      lines: [{ start: 0, end: 4, text: "So far." }],
    })
    expect(deviceLines(json)).toEqual([{ start: 0, end: 4, text: "So far." }])
  })
})
