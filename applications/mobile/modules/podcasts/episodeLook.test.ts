// LOFI-FORK: the podcasts section's episode look rules (see FORK.md).
import { describe, expect, it } from "vitest"

import { needsMore, ringFraction, rowState, splitNotes } from "./episodeLook"

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
