// LOFI-FORK: the podcasts section's player menu (see FORK.md).
import { describe, expect, it } from "vitest"

import { type MenuAction } from "@/components/ui/menu"

import { type PlayerMenuInput, playerMenuActions } from "./playerMenuActions"

const noop = () => {}
const on: PlayerMenuInput["on"] = {
  save: noop,
  share: noop,
  shareFrom: noop,
  playlist: noop,
  episode: noop,
  show: noop,
  allChapters: noop,
  previousChapter: noop,
  nextChapter: noop,
  notes: noop,
  addBookmark: noop,
  allBookmarks: noop,
  played: noop,
  settings: noop,
}

function input(extra: Partial<PlayerMenuInput> = {}): PlayerMenuInput {
  return {
    preview: false,
    saved: false,
    played: false,
    timeText: "1:02",
    hasChapters: true,
    hasShow: true,
    on,
    ...extra,
  }
}

// The rows you see at the top level: inline sections are only separators, so look inside them.
function topRows(actions: MenuAction[]): MenuAction[] {
  return actions.flatMap((action) =>
    action.displayInline ? (action.subactions ?? []) : [action],
  )
}

function allIds(actions: MenuAction[]): string[] {
  return actions.flatMap((action) => [
    ...(action.id ? [action.id] : []),
    ...allIds(action.subactions ?? []),
  ])
}

describe("playerMenuActions", () => {
  it("has at most 10 top-level rows with chapters and 9 without", () => {
    expect(topRows(playerMenuActions(input())).length).toBeLessThanOrEqual(10)
    expect(
      topRows(playerMenuActions(input({ hasChapters: false }))).length,
    ).toBeLessThanOrEqual(9)
  })

  it("lays out the top level as four plain sections", () => {
    const actions = playerMenuActions(input())
    expect(actions.every((a) => a.displayInline && a.title === "")).toBe(true)
    expect(actions.map((a) => topRows([a]).map((r) => r.title))).toEqual([
      ["Save Episode", "Share", "Add to Playlist"],
      ["Go to Episode", "Go to Show"],
      ["Chapters", "Notes", "Bookmarks"],
      ["Mark as Played", "Show Settings"],
    ])
  })

  it("keeps every feature reachable", () => {
    const ids = allIds(playerMenuActions(input()))
    for (const id of [
      "save",
      "share",
      "share-from",
      "playlist",
      "episode",
      "show",
      "chapters",
      "previous",
      "next",
      "notes",
      "bookmark",
      "bookmarks",
      "played",
      "settings",
    ]) {
      expect(ids).toContain(id)
    }
  })

  it("uses unique ids, so every press finds its callback", () => {
    const ids = allIds(playerMenuActions(input()))
    expect(new Set(ids).size).toBe(ids.length)
  })

  it("names the share time and the save and played states", () => {
    const actions = playerMenuActions(input({ saved: true, played: true }))
    const titles = JSON.stringify(actions)
    expect(titles).toContain("Share from 1:02")
    expect(titles).toContain("Unsave Episode")
    expect(titles).toContain("Mark as Unplayed")
  })

  it("hides Chapters when there are none", () => {
    const ids = allIds(playerMenuActions(input({ hasChapters: false })))
    expect(ids).not.toContain("chapters")
    expect(ids).not.toContain("previous")
  })

  it("hides save, bookmarks, played, settings and Go to Episode for a preview", () => {
    const ids = allIds(playerMenuActions(input({ preview: true })))
    for (const id of [
      "save",
      "bookmark",
      "bookmarks",
      "played",
      "settings",
      "episode",
    ]) {
      expect(ids).not.toContain(id)
    }
    expect(ids).toContain("show")
    expect(ids).toContain("playlist")
  })

  it("has no Go to Show or Show Settings without a show, and no empty sections", () => {
    const actions = playerMenuActions(input({ hasShow: false }))
    const ids = allIds(actions)
    expect(ids).not.toContain("show")
    expect(ids).not.toContain("settings")
    expect(actions.every((a) => (a.subactions ?? []).length > 0)).toBe(true)
  })

  it("calls the callback of the pressed action", () => {
    let pressed = ""
    const actions = playerMenuActions(
      input({ on: { ...on, allBookmarks: () => (pressed = "all") } }),
    )
    const find = (list: MenuAction[], id: string): MenuAction | undefined => {
      for (const a of list) {
        if (a.id === id) return a
        const inner = find(a.subactions ?? [], id)
        if (inner) return inner
      }
      return undefined
    }
    find(actions, "bookmarks")?.onPress?.()
    expect(pressed).toBe("all")
  })
})
