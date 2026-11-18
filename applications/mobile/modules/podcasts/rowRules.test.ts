// LOFI-FORK: guards the podcasts section's episode rows against reading whole stores.
import { describe, expect, it } from "vitest"

import {
  callDepths,
  exportedCall,
  exportedNames,
  importsOf,
  mentionsOf,
  readSource,
} from "./testSource"

/*
 * A row on a long list must draw again only when what it shows changes. A hook that reads a
 * whole store (the route, the player's view, the download map, the whole queue) draws every
 * row again at every change of that store, so a row reads one value at a time instead:
 * `useQueued(id)`, `useDownload(id)`, `usePlayerValue(select)`, and the tab from
 * `lastTabSegments()` when a link is pressed. These tests read the source of the row files and
 * fail when any of those hooks is named in them in any way: imported, imported under another
 * name, re-exported, called through a wrapper of the same file, or read from a namespace.
 */

const WHOLE_STORES = [
  "useSegments",
  "usePathname",
  "useGlobalSearchParams",
  "useNavigationState",
  "useRootNavigationState",
  "usePlayer",
  "useDownloadMap",
  "useUpNext",
  "useSyncExternalStore",
]

const ROWS = [
  ["EpisodeRow", "podcasts/EpisodeRow.tsx"],
  ["EpisodeMenu", "podcasts/EpisodeMenu.tsx"],
  ["PlayButton", "podcasts/PlayButton.tsx"],
] as const

describe("the check that reads source", () => {
  const flagged = (source: string) => mentionsOf(source, WHOLE_STORES)

  it("finds a whole-store hook in every way a file can name it", () => {
    expect(flagged(`const x = usePlayer()`)).toEqual(["usePlayer"])
    expect(flagged(`import { useUpNext as queue } from "./useUpNext"`)).toEqual(
      ["useUpNext"],
    )
    expect(flagged(`export { useSegments } from "expo-router"`)).toEqual([
      "useSegments",
    ])
    expect(flagged(`function useWhole() { return useDownloadMap() }`)).toEqual([
      "useDownloadMap",
    ])
    expect(flagged(`import * as s from "x"; s.usePlayer()`)).toEqual([
      "usePlayer",
    ])
    expect(
      flagged(`const { usePathname: p } = require("expo-router")`),
    ).toEqual(["usePathname"])
    expect(flagged(`store["useUpNext"]()`)).toEqual(["useUpNext"])
    expect(flagged("store[`usePlayer`]()")).toEqual(["usePlayer"])
    expect(flagged(`export * from "expo-router"`)).toEqual(["export *"])
    expect(
      flagged(`export default function A() { return <usePlayer /> }`),
    ).toEqual(["usePlayer"])
  })

  it("does not count comments, longer names or a path", () => {
    expect(flagged(`// usePlayer() is read by the page\nconst a = 1`)).toEqual(
      [],
    )
    expect(flagged(`/* useSegments */ const a = 1`)).toEqual([])
    expect(flagged(`import { useQueued } from "./useUpNext"`)).toEqual([])
    expect(flagged(`const a = usePlayerValue((v) => v.isPlaying)`)).toEqual([])
    expect(flagged(``)).toEqual([])
  })

  it("reads the way a row names its parts", () => {
    const source = `
      import { memo } from "react"
      import { sameRowProps as same } from "./same"
      export const Row = memo(RowView, same)
      function RowView() { const go = () => lastTabSegments(); lastTabSegments() }
    `
    expect(exportedNames(source)).toEqual(["Row"])
    expect(importsOf(source)).toEqual([
      { local: "memo", imported: "memo", from: "react" },
      { local: "same", imported: "sameRowProps", from: "./same" },
    ])
    expect(exportedCall(source, "Row")).toEqual({
      callee: "memo",
      from: "react",
      args: ["RowView", "same"],
    })
    expect(exportedCall(source, "Missing")).toBeNull()
    expect(callDepths(source, "lastTabSegments")).toEqual([2, 1])
  })
})

describe("a row reads no whole store", () => {
  it.each(ROWS)("%s", (name, path) => {
    const source = readSource(path)
    // The file is the real one: it exports the component and calls hooks.
    expect(exportedNames(source)).toContain(name)
    expect(source.length).toBeGreaterThan(500)
    expect(mentionsOf(source, WHOLE_STORES)).toEqual([])
  })

  it("reads the queue one episode at a time", () => {
    for (const path of [
      "podcasts/EpisodeRow.tsx",
      "podcasts/EpisodeMenu.tsx",
    ]) {
      const source = readSource(path)
      expect(importsOf(source)).toContainEqual({
        local: "useQueued",
        imported: "useQueued",
        from: "./useUpNext",
      })
      expect(callDepths(source, "useQueued")).toHaveLength(1)
    }
  })

  it("reads the tab for a link only when the link is pressed", () => {
    for (const path of [
      "podcasts/EpisodeRow.tsx",
      "podcasts/EpisodeMenu.tsx",
    ]) {
      const source = readSource(path)
      expect(importsOf(source)).toContainEqual({
        local: "lastTabSegments",
        imported: "lastTabSegments",
        from: "@/modules/podcasts/lastTab",
      })
      const depths = callDepths(source, "lastTabSegments")
      expect(depths.length).toBeGreaterThan(0)
      // Inside a handler (2 or more), never in the body of the component (1).
      expect(Math.min(...depths)).toBeGreaterThanOrEqual(2)
    }
  })

  it("the play button reads the player through a selector", () => {
    const source = readSource("podcasts/PlayButton.tsx")
    expect(callDepths(source, "usePlayerValue").length).toBeGreaterThan(0)
  })
})

describe("the row is memoized", () => {
  it("EpisodeRow is exported through memo with a comparison of its props", () => {
    const source = readSource("podcasts/EpisodeRow.tsx")
    const call = exportedCall(source, "EpisodeRow")
    expect(call).toEqual({
      callee: "memo",
      from: "react",
      args: ["EpisodeRowView", "sameRowProps"],
    })
    expect(importsOf(source)).toContainEqual({
      local: "sameRowProps",
      imported: "sameRowProps",
      from: "@/modules/podcasts/sameProps",
    })
  })
})
