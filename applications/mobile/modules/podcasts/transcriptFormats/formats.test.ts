// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).
import { describe, expect, it } from "vitest"

import { kindOfType, parseTranscript } from "./index"
import { parseJson } from "./json"
import { parseSrt } from "./srt"
import { parseTimestamp } from "./timestamp"
import { TranscriptFormatError } from "./types"
import { parseVtt } from "./vtt"

describe("parseTimestamp", () => {
  it("reads hours, minutes, seconds and fractions", () => {
    expect(parseTimestamp("01:02:03.500")).toBe(3723.5)
    expect(parseTimestamp("02:03,25")).toBe(123.25)
    expect(parseTimestamp("93")).toBe(93)
    expect(parseTimestamp("93.5")).toBe(93.5)
    expect(parseTimestamp("00:00:00.5")).toBe(0.5)
    expect(parseTimestamp("10:00:00.000")).toBe(36000)
  })

  it("rejects what is not a time", () => {
    expect(parseTimestamp("")).toBeNull()
    expect(parseTimestamp("soon")).toBeNull()
    expect(parseTimestamp("1:2:3:4")).toBeNull()
  })
})

const VTT = `WEBVTT - An episode

NOTE this block is a comment
and so is this line

STYLE
::cue { color: red }

intro
00:00:01.000 --> 00:00:04.500 align:start position:10%
<v Ada Host>Welcome to the show.</v>

00:00:04.500 --> 00:00:07.000
It is <i>good</i> to be here &amp; now.

2
01:02:03.250 --> 01:02:05.000
<v.loud Ben>Past the hour mark.
`

describe("parseVtt", () => {
  it("reads cues, voice tags and times with hours", () => {
    expect(parseVtt(VTT)).toEqual([
      { start: 1, end: 4.5, speaker: "Ada Host", text: "Welcome to the show." },
      {
        start: 4.5,
        end: 7,
        speaker: "Ada Host",
        text: "It is good to be here & now.",
      },
      {
        start: 3723.25,
        end: 3725,
        speaker: "Ben",
        text: "Past the hour mark.",
      },
    ])
  })

  it("reads short times and windows line endings", () => {
    const lines = parseVtt("WEBVTT\r\n\r\n00:01.000 --> 00:02.000\r\nHello\r\n")
    expect(lines).toEqual([{ start: 1, end: 2, text: "Hello" }])
  })

  it("skips a bad cue and keeps the rest", () => {
    const lines = parseVtt(
      "WEBVTT\n\nsoon --> later\nBroken\n\n00:00:01.000 --> 00:00:02.000\nFine\n",
    )
    expect(lines.map((line) => line.text)).toEqual(["Fine"])
  })

  it("explains a file that is not WebVTT", () => {
    expect(() => parseVtt("<html>Not found</html>")).toThrow(
      TranscriptFormatError,
    )
    expect(() => parseVtt("<html>Not found</html>")).toThrow(
      "This isn't a WebVTT transcript.",
    )
  })

  it("explains a file with a header and no cues", () => {
    expect(() => parseVtt("WEBVTT\n\nNOTE nothing here\n")).toThrow(
      "This transcript has no lines that can be read.",
    )
  })
})

const SRT = `1
00:00:01,000 --> 00:00:03,500
Ada: Hello there.

2
00:00:03,500 --> 00:00:05,000
How are
you today?

3
00:59:59,900 --> 01:00:02,000
Note: a short label counts as a name
`

describe("parseSrt", () => {
  it("reads numbered cues, joins wrapped lines and finds speakers", () => {
    expect(parseSrt(SRT)).toEqual([
      { start: 1, end: 3.5, speaker: "Ada", text: "Hello there." },
      { start: 3.5, end: 5, speaker: "Ada", text: "How are you today?" },
      {
        start: 3599.9,
        end: 3602,
        speaker: "Note",
        text: "a short label counts as a name",
      },
    ])
  })

  it("explains a file that is not SRT", () => {
    expect(() => parseSrt("Just some words.")).toThrow(
      "This isn't an SRT transcript.",
    )
  })
})

describe("parseJson", () => {
  const segments = JSON.stringify({
    version: "1.0.0",
    segments: [
      { speaker: "Ada", startTime: 0, endTime: 2.5, body: "Hello." },
      { startTime: 2.5, endTime: 3723, body: "  Still   Ada. " },
      { speaker: "Ben", startTime: "3723.5", endTime: 3730, body: "Hours in." },
      { startTime: 5, endTime: 4, body: "Ends before it starts" },
      { startTime: 6, endTime: 7 },
    ],
  })

  it("reads Podcasting 2.0 segments with speakers", () => {
    expect(parseJson(segments)).toEqual([
      { start: 0, end: 2.5, speaker: "Ada", text: "Hello." },
      { start: 2.5, end: 3723, speaker: "Ada", text: "Still Ada." },
      { start: 3723.5, end: 3730, speaker: "Ben", text: "Hours in." },
    ])
  })

  it("reads a list in milliseconds", () => {
    expect(
      parseJson(JSON.stringify([{ start: 1500, end: 2500, text: "Hi" }])),
    ).toEqual([{ start: 1.5, end: 2.5, text: "Hi" }])
  })

  it("sorts lines by their start", () => {
    const lines = parseJson(
      JSON.stringify({
        segments: [
          { startTime: 5, endTime: 6, body: "b" },
          { startTime: 1, endTime: 2, body: "a" },
        ],
      }),
    )
    expect(lines.map((line) => line.text)).toEqual(["a", "b"])
  })

  it("explains broken files", () => {
    expect(() => parseJson("{nope")).toThrow("This isn't a JSON transcript.")
    expect(() => parseJson('{"title": "x"}')).toThrow(
      "This JSON isn't a transcript.",
    )
    expect(() => parseJson('{"segments": []}')).toThrow(
      "This transcript has no lines that can be read.",
    )
  })
})

describe("parseTranscript", () => {
  it("goes by what the file starts with when the type is wrong", () => {
    expect(parseTranscript(VTT, "text/plain")).toHaveLength(3)
    expect(
      parseTranscript(
        '{"segments":[{"startTime":0,"endTime":1,"body":"x"}]}',
        "text/vtt",
      ),
    ).toHaveLength(1)
  })

  it("uses the type for SRT and says HTML is not read", () => {
    expect(parseTranscript(SRT, "application/x-subrip")).toHaveLength(3)
    expect(() => parseTranscript("<p>Hello</p>", "text/html")).toThrow(
      "web page",
    )
  })

  it("names the formats from their types", () => {
    expect(kindOfType("application/json; charset=utf-8")).toBe("json")
    expect(kindOfType("Text/VTT")).toBe("vtt")
    expect(kindOfType("application/x-subrip")).toBe("srt")
    expect(kindOfType("text/html")).toBe("html")
    expect(kindOfType("text/plain")).toBeNull()
    expect(kindOfType(null)).toBeNull()
  })
})
