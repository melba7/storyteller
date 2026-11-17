// LOFI-FORK: the podcasts section's episode menu rules (see FORK.md).
import { describe, expect, it } from "vitest"

import { type MenuFacts, downloadIcon, menuLayout } from "./episodeMenuModel"

const facts: MenuFacts = {
  starred: false,
  played: false,
  archived: false,
  queued: false,
  preview: false,
  download: {
    title: "Download",
    destructive: false,
    icon: "arrow.down.circle",
  },
}
const titles = (items: { title: string }[]) => items.map((item) => item.title)

describe("menuLayout", () => {
  it("is Apple's order for an episode in the library", () => {
    const layout = menuLayout(facts)
    expect(titles(layout.top)).toEqual(["Save", "Share"])
    expect(layout.groups.map(titles)).toEqual([
      ["Play Next", "Play Last", "Mark as Played"],
      ["Go to Episode", "Go to Show", "View Transcript", "Add to Playlist"],
      ["Archive"],
      ["Download"],
    ])
  })

  it("flips the words of Save, played and Archive", () => {
    const layout = menuLayout({
      ...facts,
      starred: true,
      played: true,
      archived: true,
    })
    expect(titles(layout.top)).toEqual(["Unsave", "Share"])
    expect(titles(layout.groups[0]!)).toContain("Mark as Unplayed")
    expect(titles(layout.groups[2]!)).toEqual(["Unarchive"])
  })

  it("adds Remove from Up Next for a queued episode, in red", () => {
    const items = menuLayout({ ...facts, queued: true }).groups[0]!
    expect(titles(items)).toEqual([
      "Play Next",
      "Play Last",
      "Remove from Up Next",
      "Mark as Played",
    ])
    expect(items[2]?.destructive).toBe(true)
  })

  it("puts a destructive Remove Download last", () => {
    const layout = menuLayout({
      ...facts,
      download: { title: "Remove Download", destructive: true, icon: "trash" },
    })
    const last = layout.groups[layout.groups.length - 1]!
    expect(last).toEqual([
      {
        id: "download",
        title: "Remove Download",
        icon: "trash",
        destructive: true,
      },
    ])
  })

  it("keeps an added file's actions after Archive", () => {
    const layout = menuLayout({
      ...facts,
      extra: [
        { id: "rename", title: "Rename", icon: "pencil" },
        {
          id: "delete-file",
          title: "Delete file",
          icon: "trash",
          destructive: true,
        },
      ],
    })
    expect(titles(layout.groups[2]!)).toEqual([
      "Archive",
      "Rename",
      "Delete file",
    ])
  })

  it("has no library actions for a preview episode and no empty group", () => {
    const layout = menuLayout({ ...facts, preview: true, download: null })
    expect(titles(layout.top)).toEqual(["Share"])
    expect(layout.groups.map(titles)).toEqual([
      ["Play Next", "Play Last"],
      ["Add to Playlist"],
    ])
  })

  it("names the symbol of each download action", () => {
    expect(downloadIcon("download")).toBe("arrow.down.circle")
    expect(downloadIcon("retry")).toBe("arrow.down.circle")
    expect(downloadIcon("cancel")).toBe("xmark.circle")
    expect(downloadIcon("delete")).toBe("trash")
  })
})
