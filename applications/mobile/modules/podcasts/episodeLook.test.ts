// LOFI-FORK: the podcasts section's episode look rules (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  needsMore,
  playLabel,
  ringFraction,
  rowMeta,
  rowState,
  showMeta,
  splitNotes,
} from "./episodeLook"

const episode = (
  positionSeconds: number,
  durationSeconds: number | null,
  played = false,
) => ({ positionSeconds, durationSeconds, played })

describe("rowState", () => {
  it("is unplayed at the start", () => {
    expect(rowState(episode(0, 600))).toBe("unplayed")
  })
  it("is inProgress once the listener has moved on", () => {
    expect(rowState(episode(120, 600))).toBe("inProgress")
  })
  it("is played whenever the flag is set, even with a place kept", () => {
    expect(rowState(episode(0, 600, true))).toBe("played")
    expect(rowState(episode(590, 600, true))).toBe("played")
  })
})

describe("ringFraction", () => {
  it("is the share listened", () => {
    expect(ringFraction(episode(150, 600))).toBe(0.25)
  })
  it("is 0 for an unplayed episode and for an unknown length", () => {
    expect(ringFraction(episode(0, 600))).toBe(0)
    expect(ringFraction(episode(100, null))).toBe(0)
    expect(ringFraction(episode(100, 0))).toBe(0)
  })
  it("stays between 0 and 1", () => {
    expect(ringFraction(episode(900, 600))).toBe(1)
    expect(ringFraction(episode(-5, 600))).toBe(0)
  })
  it("is null for a played episode, so no ring is drawn", () => {
    expect(ringFraction(episode(300, 600, true))).toBeNull()
  })
})

describe("splitNotes", () => {
  const link = (url: string) => ({ type: "link", text: url, url })
  const text = (value: string) => ({ type: "text", text: value })

  it("returns one text part when there is no link", () => {
    expect(splitNotes("Just words.")).toEqual([text("Just words.")])
    expect(splitNotes("")).toEqual([])
  })
  it("finds http and https links", () => {
    expect(splitNotes("a http://x.com b https://y.org/p?q=1 c")).toEqual([
      text("a "),
      link("http://x.com"),
      text(" b "),
      link("https://y.org/p?q=1"),
      text(" c"),
    ])
  })
  it("leaves trailing punctuation out of the link", () => {
    expect(splitNotes("see https://x.com/a.")).toEqual([
      text("see "),
      link("https://x.com/a"),
      text("."),
    ])
    expect(splitNotes("https://x.com/a, https://x.com/b!?")).toEqual([
      link("https://x.com/a"),
      text(", "),
      link("https://x.com/b"),
      text("!?"),
    ])
  })
  it("leaves a closing parenthesis out when the link was in parentheses", () => {
    expect(splitNotes("(see https://x.com/a)")).toEqual([
      text("(see "),
      link("https://x.com/a"),
      text(")"),
    ])
    expect(splitNotes("(https://x.com/a).")).toEqual([
      text("("),
      link("https://x.com/a"),
      text(")."),
    ])
  })
  it("keeps a parenthesis that belongs to the address", () => {
    expect(splitNotes("https://en.wikipedia.org/wiki/Rust_(language)")).toEqual(
      [link("https://en.wikipedia.org/wiki/Rust_(language)")],
    )
  })
  it("ignores other schemes and bare schemes", () => {
    expect(splitNotes("ftp://x.com and https:// alone")).toEqual([
      text("ftp://x.com and https:// alone"),
    ])
  })
  it("keeps line breaks in the text parts", () => {
    expect(splitNotes("a\nhttps://x.com\nb")).toEqual([
      text("a\n"),
      link("https://x.com"),
      text("\nb"),
    ])
  })
})

describe("needsMore", () => {
  it("is false for a short description", () => {
    expect(needsMore("A show about birds.")).toBe(false)
    expect(needsMore("")).toBe(false)
  })
  it("is true for a long description", () => {
    expect(needsMore("word ".repeat(60))).toBe(true)
  })
  it("is true for several short lines", () => {
    expect(needsMore("a\nb\nc\nd")).toBe(true)
    expect(needsMore("a\nb\nc")).toBe(false)
  })
})

describe("rowMeta", () => {
  const base = { state: "unplayed" as const, length: "45 min", queued: "" }

  it("is just the length for a plain episode", () => {
    const meta = rowMeta(base)
    expect(meta).toEqual({
      glyph: "none",
      fraction: null,
      length: "45 min",
      queued: false,
      spoken: ["45 min"],
    })
  })

  it("says Downloaded, with a check glyph", () => {
    const meta = rowMeta({
      ...base,
      download: { episodeId: "e", state: "downloaded", updatedAt: 0 },
    })
    expect(meta.glyph).toBe("downloaded")
    expect(meta.spoken).toEqual(["Downloaded", "45 min"])
  })

  it("says Downloading with the percent, and gives the ring's fraction", () => {
    const meta = rowMeta({
      ...base,
      download: {
        episodeId: "e",
        state: "downloading",
        bytes: 400,
        updatedAt: 0,
        expected: 1000,
      },
    })
    expect(meta.glyph).toBe("downloading")
    expect(meta.fraction).toBeCloseTo(0.4)
    expect(meta.spoken[0]).toBe("Downloading, 40%")
  })

  it("says Downloading without a percent when the size is unknown", () => {
    const meta = rowMeta({
      ...base,
      download: { episodeId: "e", state: "downloading", updatedAt: 0 },
    })
    expect(meta.fraction).toBeNull()
    expect(meta.spoken[0]).toBe("Downloading")
  })

  it("says Waiting to download for a queued download", () => {
    const meta = rowMeta({
      ...base,
      download: { episodeId: "e", state: "queued", updatedAt: 0 },
    })
    expect(meta.glyph).toBe("downloading")
    expect(meta.spoken[0]).toBe("Waiting to download")
  })

  it("flags a failed download", () => {
    const meta = rowMeta({
      ...base,
      download: { episodeId: "e", state: "failed", updatedAt: 0 },
    })
    expect(meta.glyph).toBe("failed")
    expect(meta.spoken[0]).toBe("Download failed")
  })

  it("shows a check and says Played for a played episode", () => {
    const meta = rowMeta({ ...base, state: "played", length: "Played" })
    expect(meta.glyph).toBe("played")
    expect(meta.spoken).toEqual(["Played"])
  })

  it("lets a download glyph win over the played check but keeps the word", () => {
    const meta = rowMeta({
      state: "played",
      length: "Played",
      queued: "",
      download: { episodeId: "e", state: "downloaded", updatedAt: 0 },
    })
    expect(meta.glyph).toBe("downloaded")
    expect(meta.spoken).toEqual(["Downloaded", "Played"])
  })

  it("gives the time left, then Up Next in the visible line and in the words", () => {
    const meta = rowMeta({
      state: "inProgress",
      length: "12 min left",
      queued: "Up Next, number 2",
    })
    expect(meta.length).toBe("12 min left")
    expect(meta.queued).toBe(true)
    expect(meta.spoken).toEqual(["12 min left", "Up Next, number 2"])
  })

  it("has no words for an episode of unknown length", () => {
    expect(rowMeta({ ...base, length: "" }).spoken).toEqual([])
  })
})

describe("showMeta", () => {
  it("joins the first top-level category and the episode count", () => {
    expect(showMeta(["Comedy › Improv", "Comedy"], 214)).toBe(
      "Comedy · 214 episodes",
    )
  })
  it("says 1 episode for one", () => {
    expect(showMeta(["News"], 1)).toBe("News · 1 episode")
  })
  it("leaves out what it doesn't know", () => {
    expect(showMeta([], 3)).toBe("3 episodes")
    expect(showMeta(["Arts"], null)).toBe("Arts")
    expect(showMeta([], null)).toBe("")
  })
  it("falls back to a sub-category when that's all there is", () => {
    expect(showMeta(["Arts › Books"], null)).toBe("Arts › Books")
  })
})

describe("playLabel", () => {
  it("says Play for an episode not started, or played", () => {
    expect(playLabel(episode(0, 600), false)).toBe("Play")
    expect(playLabel(episode(300, 600, true), false)).toBe("Play")
  })
  it("says Resume with the time left for one in progress", () => {
    expect(playLabel(episode(1920, 3840), false)).toBe("Resume · 32 min left")
  })
  it("says Resume alone when the length is unknown", () => {
    expect(playLabel(episode(120, null), false)).toBe("Resume")
  })
  it("says Pause while it plays", () => {
    expect(playLabel(episode(1920, 3840), true)).toBe("Pause")
  })
})
