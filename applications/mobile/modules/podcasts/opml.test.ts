// LOFI-FORK: the podcasts section's OPML reading and writing (see FORK.md).
import { describe, expect, it } from "vitest"

import { OpmlError, parseOpml, writeOpml } from "./opml"

// Fixtures written by hand, in the shapes other podcast apps produce.
const FLAT = `<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head><title>My shows</title></head>
  <body>
    <outline type="rss" text="Show One" title="Show One" xmlUrl="https://one.example.com/feed.xml" htmlUrl="https://one.example.com"/>
    <outline type="rss" text="Show Two" xmlUrl='https://two.example.com/rss'/>
  </body>
</opml>`

const NESTED = `<?xml version="1.0"?>
<!-- exported by hand -->
<opml version="1.0">
  <head/>
  <body>
    <outline text="Tech">
      <outline text="Deep">
        <outline type="rss" text="Show A" xmlUrl="https://a.example.com/feed"/>
      </outline>
      <outline type="rss" text="Show B" xmlUrl="https://b.example.com/feed"/>
    </outline>
    <outline text="Empty folder"></outline>
    <outline type="rss" text="Show C" xmlUrl="https://c.example.com/feed"/>
  </body>
</opml>`

describe("a very large file", () => {
  it("is read quickly", () => {
    const outlines = Array.from(
      { length: 5000 },
      (_, at) =>
        `<outline type="rss" text="Show ${at}" xmlUrl="https://example.com/${at}.xml"/>`,
    ).join("\n")
    const xml = `<?xml version="1.0"?><opml version="2.0"><body>${outlines}</body></opml>`
    const started = Date.now()
    expect(parseOpml(xml).feeds).toHaveLength(5000)
    expect(Date.now() - started).toBeLessThan(1000)
  })
})

describe("parseOpml", () => {
  it("reads the feed addresses and names", () => {
    expect(parseOpml(FLAT)).toEqual({
      feeds: [
        { title: "Show One", feedUrl: "https://one.example.com/feed.xml" },
        { title: "Show Two", feedUrl: "https://two.example.com/rss" },
      ],
      ignored: 0,
    })
  })

  it("looks through nested outlines, in file order", () => {
    expect(parseOpml(NESTED).feeds.map((feed) => feed.title)).toEqual([
      "Show A",
      "Show B",
      "Show C",
    ])
  })

  it("skips outlines with no xmlUrl and counts the empty ones", () => {
    const xml = `<opml><body>
      <outline text="No address"/>
      <outline text="Has one" xmlUrl="https://x.example.com/f"/>
      <outline text="Blank" xmlUrl="  "/>
    </body></opml>`
    expect(parseOpml(xml)).toEqual({
      feeds: [{ title: "Has one", feedUrl: "https://x.example.com/f" }],
      ignored: 2,
    })
  })

  it("prefers title, falls back to text, then to nothing", () => {
    const xml = `<opml><body>
      <outline text="Text" title="Title" xmlUrl="https://a.example.com/f"/>
      <outline text="Only text" xmlUrl="https://b.example.com/f"/>
      <outline xmlUrl="https://c.example.com/f"/>
    </body></opml>`
    expect(parseOpml(xml).feeds.map((feed) => feed.title)).toEqual([
      "Title",
      "Only text",
      "",
    ])
  })

  it("decodes escaped characters, also in the address", () => {
    const xml = `<opml><body>
      <outline text="Tom &amp; Jerry &quot;Live&quot; &#233;&#x1F600; &lt;3" xmlUrl="https://a.example.com/f?x=1&amp;y=2"/>
    </body></opml>`
    expect(parseOpml(xml).feeds).toEqual([
      {
        title: 'Tom & Jerry "Live" é\u{1F600} <3',
        feedUrl: "https://a.example.com/f?x=1&y=2",
      },
    ])
  })

  it("accepts a > inside a quoted value, CDATA and a byte order mark", () => {
    const xml = `﻿<opml><head><title><![CDATA[<odd>]]></title></head><body>
      <outline text="a > b" xmlUrl="https://a.example.com/f"/>
    </body></opml>`
    expect(parseOpml(xml).feeds[0]?.title).toBe("a > b")
  })

  it("reads attribute names in any case", () => {
    const xml = `<OPML><BODY><OUTLINE TEXT="Shout" XMLURL="https://a.example.com/f"/></BODY></OPML>`
    expect(parseOpml(xml).feeds).toHaveLength(1)
  })

  it("ignores outlines outside the body", () => {
    const xml = `<opml><head><outline xmlUrl="https://a.example.com/f"/></head><body/></opml>`
    expect(parseOpml(xml).feeds).toEqual([])
  })

  it("gives an empty list for an empty body", () => {
    expect(parseOpml("<opml><body></body></opml>")).toEqual({
      feeds: [],
      ignored: 0,
    })
  })
})

describe("parseOpml with a broken file", () => {
  function messageFor(xml: string): string {
    try {
      parseOpml(xml)
    } catch (cause) {
      expect(cause).toBeInstanceOf(OpmlError)
      return (cause as Error).message
    }
    throw new Error("It should have thrown.")
  }

  it("says an empty file is empty", () => {
    expect(messageFor("")).toBe("This file is empty.")
    expect(messageFor("  \n ")).toBe("This file is empty.")
  })

  it("says what is not OPML", () => {
    expect(messageFor("just some words")).toContain("doesn't look like an OPML")
    expect(messageFor("<rss version='2.0'><channel/></rss>")).toContain(
      "doesn't look like an OPML",
    )
  })

  it("names an unclosed tag", () => {
    expect(
      messageFor(
        '<opml><body><outline text="a" xmlUrl="https://a.example.com/f">',
      ),
    ).toContain("<outline> is never closed")
  })

  it("names a closing tag that does not match, with the line", () => {
    const message = messageFor("<opml>\n<body>\n</head>\n</opml>")
    expect(message).toContain("</head> has no matching opening tag")
    expect(message).toContain("line 3")
  })

  it("names an unfinished attribute", () => {
    expect(
      messageFor('<opml><body><outline text="a/></body></opml>'),
    ).toContain('the attribute "text" is never closed')
    expect(messageFor("<opml><body><outline text=a/></body></opml>")).toContain(
      "has no quotes",
    )
    expect(messageFor("<opml><body><outline text/></body></opml>")).toContain(
      "has no value",
    )
  })

  it("names an unfinished comment and a cut-off tag", () => {
    expect(messageFor("<opml><!-- oops <body/></opml>")).toContain(
      "a comment is never closed",
    )
    expect(messageFor("<opml><body><outline text='a'")).toContain(
      "the <outline> tag is never closed",
    )
  })
})

describe("writeOpml", () => {
  const now = new Date(Date.UTC(2026, 10, 17, 3, 0, 0))

  it("writes one outline for each show", () => {
    const xml = writeOpml(
      [
        {
          title: "Show One",
          feedUrl: "https://one.example.com/feed.xml",
          link: "https://one.example.com",
        },
        {
          title: "Show Two",
          feedUrl: "https://two.example.com/rss",
          link: null,
        },
      ],
      now,
    )
    expect(
      xml.startsWith(
        '<?xml version="1.0" encoding="UTF-8"?>\n<opml version="2.0">',
      ),
    ).toBe(true)
    expect(xml).toContain(
      "<dateCreated>Tue, 17 Nov 2026 03:00:00 GMT</dateCreated>",
    )
    expect(xml).toContain(
      '<outline type="rss" text="Show One" title="Show One" xmlUrl="https://one.example.com/feed.xml" htmlUrl="https://one.example.com"/>',
    )
    expect(xml).toContain(
      '<outline type="rss" text="Show Two" title="Show Two" xmlUrl="https://two.example.com/rss"/>',
    )
  })

  it("escapes names and addresses", () => {
    const xml = writeOpml(
      [
        {
          title: `Tom & "Jerry" <Live> it's`,
          feedUrl: "https://a.example.com/f?x=1&y=2",
        },
      ],
      now,
    )
    expect(xml).toContain(
      'text="Tom &amp; &quot;Jerry&quot; &lt;Live&gt; it&apos;s"',
    )
    expect(xml).toContain('xmlUrl="https://a.example.com/f?x=1&amp;y=2"')
  })

  it("reads back as the same shows", () => {
    const shows = [
      {
        title: `Tom & "Jerry" <Live> é`,
        feedUrl: "https://a.example.com/f?x=1&y=2",
        link: null,
      },
      {
        title: "Plain",
        feedUrl: "https://b.example.com/rss",
        link: "https://b.example.com",
      },
    ]
    expect(parseOpml(writeOpml(shows, now))).toEqual({
      feeds: shows.map(({ title, feedUrl }) => ({ title, feedUrl })),
      ignored: 0,
    })
  })

  it("writes a valid file for no shows", () => {
    expect(parseOpml(writeOpml([], now))).toEqual({ feeds: [], ignored: 0 })
  })
})
