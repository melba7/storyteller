// LOFI-FORK: guards the podcasts section's list pages against drawing on every tick.
import { describe, expect, it } from "vitest"

import {
  attributesOf,
  callDepths,
  declaredAs,
  exportedNames,
  importsOf,
  mentionsOf,
  readSource,
} from "./testSource"

/*
 * A list page must not draw again at every tick of the download map (every progress step of
 * any download) or of the player's view (twice a second while anything plays). It reads the
 * finished downloads with `useDownloadedIds()` and one player value at a time with
 * `usePlayerValue(select)`. Its list gets a render function and a key function that keep
 * their identity, with `strictMode` so FlatList does not hand every row a new one. These
 * tests read the code of the screens (see testSource.ts) and fail when a whole-store hook is
 * named in any way, imported under another name, re-exported or wrapped in the same file.
 */

const WHOLE_STORES = [
  "useDownloadMap",
  "usePlayer",
  "useUpNext",
  "useSyncExternalStore",
]

const SCREENS = [
  ["PodcastShow", "podcasts/PodcastShow.tsx"],
  ["EpisodeListScreen", "podcasts/EpisodeListScreen.tsx"],
  ["PlaylistScreen", "podcasts/PlaylistScreen.tsx"],
  ["PodcastEpisode", "podcasts/PodcastEpisode.tsx"],
] as const

const LISTS = SCREENS.filter(([name]) => name !== "PodcastEpisode")

describe("a list page reads no whole store", () => {
  it.each(SCREENS)("%s", (name, path) => {
    const source = readSource(path)
    // The file is the real one: it exports the screen and calls hooks.
    expect(exportedNames(source)).toContain(name)
    expect(source.length).toBeGreaterThan(500)
    expect(mentionsOf(source, WHOLE_STORES)).toEqual([])
  })

  it("the hook a smart playlist reads its downloads with reads no whole map either", () => {
    // PlaylistScreen calls useSmartEpisodes, which is where the download map was read.
    const source = readSource("podcasts/usePlaylists.ts")
    expect(exportedNames(source)).toContain("useSmartEpisodes")
    expect(mentionsOf(source, WHOLE_STORES)).toEqual([])
  })

  it("the show page and the smart playlists read the finished downloads", () => {
    for (const path of [
      "podcasts/PodcastShow.tsx",
      "podcasts/usePlaylists.ts",
    ]) {
      const source = readSource(path)
      expect(importsOf(source)).toContainEqual({
        local: "useDownloadedIds",
        imported: "useDownloadedIds",
        from: "./useDownloads",
      })
      expect(callDepths(source, "useDownloadedIds")).toHaveLength(1)
    }
  })

  it("the episode page reads the player one value at a time", () => {
    const source = readSource("podcasts/PodcastEpisode.tsx")
    expect(importsOf(source)).toContainEqual({
      local: "usePlayerValue",
      imported: "usePlayerValue",
      from: "@/modules/podcasts/playerInstance",
    })
    expect(callDepths(source, "usePlayerValue").length).toBeGreaterThan(0)
  })
})

describe("a list keeps its render function and its key function", () => {
  it.each(LISTS)("%s", (_name, path) => {
    const source = readSource(path)
    const lists = attributesOf(source, "FlatList", "renderItem")
    // The list is there, and its functions are names, not functions written in place.
    expect(lists).toHaveLength(1)
    expect(lists[0]?.type).toBe("Identifier")
    expect(attributesOf(source, "FlatList", "keyExtractor")).toEqual([
      expect.objectContaining({ type: "Identifier" }),
    ])
    const render = lists[0]?.name ?? ""
    const key = attributesOf(source, "FlatList", "keyExtractor")[0]?.name ?? ""
    // The render function is a useCallback in the screen (lint checks its dependencies);
    // the key function closes over nothing, so it sits at the top of the file.
    expect(declaredAs(source, render)).toEqual({ how: "useCallback", depth: 1 })
    expect(declaredAs(source, key)?.depth).toBe(0)
    // FlatList hands every row a new render function unless it is told to remember it.
    expect(attributesOf(source, "FlatList", "strictMode")).toEqual([
      { type: "true", name: "" },
    ])
  })

  it("a row gets the same `here` every time", () => {
    const source = readSource("podcasts/PodcastShow.tsx")
    const here = attributesOf(source, "EpisodeRow", "here")
    expect(here).toHaveLength(1)
    expect(here[0]?.type).toBe("Identifier")
    expect(declaredAs(source, here[0]?.name ?? "")?.depth).toBe(0)
  })
})

describe("the check that reads a list", () => {
  it("tells an inline function from a name, and a call from a constant", () => {
    const inline = `const A = () => <FlatList renderItem={({ item }) => item} strictMode />`
    expect(attributesOf(inline, "FlatList", "renderItem")).toEqual([
      { type: "ArrowFunctionExpression", name: "" },
    ])
    expect(attributesOf(inline, "FlatList", "strictMode")).toEqual([
      { type: "true", name: "" },
    ])
    const named = `
      const key = (x) => x.id
      function A() {
        const render = useCallback((i) => i, [])
        return <FlatList<Item> renderItem={render} keyExtractor={key} />
      }
    `
    expect(attributesOf(named, "FlatList", "renderItem")).toEqual([
      { type: "Identifier", name: "render" },
    ])
    expect(attributesOf(named, "Other", "renderItem")).toEqual([])
    expect(declaredAs(named, "render")).toEqual({
      how: "useCallback",
      depth: 1,
    })
    expect(declaredAs(named, "key")).toEqual({
      how: "ArrowFunctionExpression",
      depth: 0,
    })
    expect(declaredAs(named, "A")).toEqual({ how: "function", depth: 0 })
    expect(declaredAs(named, "missing")).toBeNull()
  })

  it("finds a whole-store hook in a hook of the same file", () => {
    const source = `
      import { useDownloadMap as map } from "./useDownloads"
      function useIds() { return map() }
    `
    expect(mentionsOf(source, WHOLE_STORES)).toEqual(["useDownloadMap"])
    expect(mentionsOf(`const a = useDownloadedIds()`, WHOLE_STORES)).toEqual([])
  })
})
