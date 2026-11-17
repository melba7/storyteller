// LOFI-FORK: the podcasts section's OPML reading and writing (see FORK.md).
//
// OPML is the file other podcast apps use to move your shows. This reads one (a small
// hand-written XML reader, since the app has no XML library) and writes one. Pure text in and
// out, so it is tested without the app. Following the shows is in opmlImport.ts.

import { feedShows } from "./localFiles"

export type OpmlFeed = {
  /** The outline's `title`, or its `text`, or "". */
  title: string
  /** The `xmlUrl` as written in the file, trimmed. */
  feedUrl: string
}

export type OpmlContents = {
  feeds: OpmlFeed[]
  /** Outlines with no feed address and nothing inside them (they are not shows). */
  ignored: number
}

/** A file that is not OPML or is damaged. The message is for the listener. */
export class OpmlError extends Error {}

// MARK: Reading

const ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
}

function decode(text: string): string {
  return text.replace(
    /&(#x[0-9a-f]+|#\d+|[a-z]+);/gi,
    (whole, name: string) => {
      if (name.startsWith("#")) {
        const code =
          name[1] === "x" || name[1] === "X"
            ? Number.parseInt(name.slice(2), 16)
            : Number.parseInt(name.slice(1), 10)
        return code > 0 &&
          code <= 0x10ffff &&
          !(code >= 0xd800 && code < 0xe000)
          ? String.fromCodePoint(code)
          : whole
      }
      return ENTITIES[name] ?? whole
    },
  )
}

type Reader = { text: string; at: number }

function damaged(reader: Reader, what: string): OpmlError {
  const line = reader.text.slice(0, reader.at).split("\n").length
  return new OpmlError(`This OPML file is damaged: ${what} (line ${line}).`)
}

function skipSpace(reader: Reader) {
  while (/\s/.test(reader.text[reader.at] ?? "x")) reader.at += 1
}

/** Moves past `end`, which must come after the current place. */
function skipTo(reader: Reader, end: string, what: string) {
  const found = reader.text.indexOf(end, reader.at)
  if (found < 0) throw damaged(reader, what)
  reader.at = found + end.length
}

/** Reads `name="value" ...` up to the tag's end. Returns the attributes and whether it closed. */
function readTag(reader: Reader): {
  name: string
  attrs: Map<string, string>
  selfClosing: boolean
} {
  const nameEnd = /[\s/>]/.exec(reader.text.slice(reader.at))
  const length = nameEnd ? nameEnd.index : reader.text.length - reader.at
  const name = reader.text.slice(reader.at, reader.at + length)
  if (name === "") throw damaged(reader, "a tag has no name")
  reader.at += length
  const attrs = new Map<string, string>()
  for (;;) {
    skipSpace(reader)
    const next = reader.text[reader.at]
    if (next === undefined)
      throw damaged(reader, `the <${name}> tag is never closed`)
    if (next === ">") {
      reader.at += 1
      return { name, attrs, selfClosing: false }
    }
    if (reader.text.startsWith("/>", reader.at)) {
      reader.at += 2
      return { name, attrs, selfClosing: true }
    }
    const key = /^[^\s=/>]+/.exec(reader.text.slice(reader.at))?.[0]
    if (!key) throw damaged(reader, `a stray "${next}" inside <${name}>`)
    reader.at += key.length
    skipSpace(reader)
    if (reader.text[reader.at] !== "=") {
      throw damaged(reader, `the attribute "${key}" has no value`)
    }
    reader.at += 1
    skipSpace(reader)
    const quote = reader.text[reader.at]
    if (quote !== '"' && quote !== "'") {
      throw damaged(reader, `the attribute "${key}" has no quotes`)
    }
    reader.at += 1
    const close = reader.text.indexOf(quote, reader.at)
    if (close < 0)
      throw damaged(reader, `the attribute "${key}" is never closed`)
    attrs.set(key.toLowerCase(), decode(reader.text.slice(reader.at, close)))
    reader.at = close + 1
  }
}

/**
 * The shows in an OPML file: every `outline` inside `body`, at any depth, that has an
 * `xmlUrl`. Folders (outlines that hold others) are looked through. Throws an OpmlError with
 * a readable message for a file that is empty, is not OPML or is not well-formed.
 */
export function parseOpml(source: string): OpmlContents {
  const reader: Reader = { text: source.replace(/^﻿/, ""), at: 0 }
  if (reader.text.trim() === "") throw new OpmlError("This file is empty.")
  const open: string[] = []
  const feeds: OpmlFeed[] = []
  let ignored = 0
  let sawRoot = false

  for (;;) {
    const lt = reader.text.indexOf("<", reader.at)
    if (lt < 0) break
    reader.at = lt
    if (reader.text.startsWith("<!--", lt)) {
      skipTo(reader, "-->", "a comment is never closed")
    } else if (reader.text.startsWith("<![CDATA[", lt)) {
      skipTo(reader, "]]>", "a CDATA section is never closed")
    } else if (reader.text.startsWith("<?", lt)) {
      skipTo(reader, "?>", "an <? ?> line is never closed")
    } else if (reader.text.startsWith("<!", lt)) {
      skipTo(reader, ">", "a <! > line is never closed")
    } else if (reader.text.startsWith("</", lt)) {
      reader.at += 2
      const end = reader.text.indexOf(">", reader.at)
      if (end < 0) throw damaged(reader, "a closing tag is never finished")
      const name = reader.text.slice(reader.at, end).trim().toLowerCase()
      if (open.pop() !== name)
        throw damaged(reader, `</${name}> has no matching opening tag`)
      reader.at = end + 1
    } else {
      reader.at += 1
      const tag = readTag(reader)
      const name = tag.name.toLowerCase()
      if (!sawRoot) {
        if (name !== "opml") {
          throw new OpmlError(
            "This doesn't look like an OPML file: it has no <opml> section.",
          )
        }
        sawRoot = true
      }
      if (name === "outline" && open.includes("body")) {
        const feedUrl = tag.attrs.get("xmlurl")?.trim() ?? ""
        if (feedUrl !== "") {
          const title = (
            tag.attrs.get("title") ??
            tag.attrs.get("text") ??
            ""
          ).trim()
          feeds.push({ title, feedUrl })
        } else if (tag.selfClosing) {
          ignored += 1
        }
      }
      if (!tag.selfClosing) open.push(name)
    }
  }
  if (!sawRoot) {
    throw new OpmlError(
      "This doesn't look like an OPML file: it has no <opml> section.",
    )
  }
  if (open.length > 0) {
    reader.at = reader.text.length
    throw damaged(reader, `<${open[open.length - 1]}> is never closed`)
  }
  return { feeds, ignored }
}

// MARK: Writing

function escape(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;")
}

/** An OPML 2.0 file listing these shows, one outline each. */
export function writeOpml(
  shows: readonly { title: string; feedUrl: string; link?: string | null }[],
  now: Date,
): string {
  const lines = feedShows(shows).map((show) => {
    const title = escape(show.title)
    const web = show.link ? ` htmlUrl="${escape(show.link)}"` : ""
    return `    <outline type="rss" text="${title}" title="${title}" xmlUrl="${escape(show.feedUrl)}"${web}/>`
  })
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<opml version="2.0">',
    "  <head>",
    "    <title>Podcasts</title>",
    `    <dateCreated>${now.toUTCString()}</dateCreated>`,
    "  </head>",
    "  <body>",
    ...lines,
    "  </body>",
    "</opml>",
    "",
  ].join("\n")
}
