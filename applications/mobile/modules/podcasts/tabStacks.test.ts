// LOFI-FORK: tests for the podcasts section's tab stacks (see FORK.md).
//
// Each tab has its own stack, and the stack's first screen is what the tab shows when it
// opens. Expo Router picks that screen from the layout's `unstable_settings.anchor`, or
// else from its own order, which puts the shortest static name first. The shared screens
// (preview, show, episode) sit in every tab's group, so without an anchor the Discover tab
// opened on an empty show preview ("preview" is shorter than "discover").
import { readFileSync, readdirSync, statSync } from "node:fs"
import { createRequire } from "node:module"
import { join, relative } from "node:path"

import { describe, expect, it } from "vitest"

const require = createRequire(import.meta.url)
const appDir = join(__dirname, "../../app")

type RouteNode = {
  route: string
  type: string
  children: RouteNode[]
}

const { getRoutes } = require("expo-router/build/getRoutes") as {
  getRoutes(context: unknown, options: object): RouteNode
}
const { getValidInitialRouteName } = require("expo-router/build/routeNode") as {
  getValidInitialRouteName(node: RouteNode): string | undefined
}
const { sortRoutesWithInitial } = require("expo-router/build/sortRoutes") as {
  sortRoutesWithInitial(
    initial: string | undefined,
  ): (a: RouteNode, b: RouteNode) => number
}

function routeFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return routeFiles(path)
    return /\.tsx?$/.test(name) ? [`./${relative(appDir, path)}`] : []
  })
}

/** A layout's anchor, read from its source, since the module itself needs the app. */
function anchorOf(file: string) {
  const source = readFileSync(join(appDir, file), "utf8")
  const anchor = /unstable_settings\s*=\s*\{\s*anchor:\s*"([^"]+)"/.exec(source)
  return anchor ? { anchor: anchor[1] } : undefined
}

function appRoutes(): RouteNode {
  const files = routeFiles(appDir)
  const context = Object.assign(
    (file: string) => ({
      default: () => null,
      unstable_settings: file.endsWith("_layout.tsx")
        ? anchorOf(file)
        : undefined,
    }),
    { keys: () => files, resolve: (file: string) => file, id: "app" },
  )
  return getRoutes(context, {
    platform: "ios",
    skipGenerated: true,
    importMode: "sync",
  })
}

function findGroup(node: RouteNode, name: string): RouteNode | undefined {
  if (node.route === name) return node
  for (const child of node.children) {
    const found = findGroup(child, name)
    if (found) return found
  }
  return undefined
}

/** The screen a tab's stack shows first. */
function firstScreen(tab: string): string | undefined {
  const group = findGroup(appRoutes(), tab)
  if (!group) throw new Error(`No ${tab} group`)
  const initial = getValidInitialRouteName(group)
  return [...group.children].sort(sortRoutesWithInitial(initial))[0]?.route
}

describe("the podcasts tabs", () => {
  it("open on their own home screen, never on a shared screen", () => {
    for (const tab of ["(home)", "(new)", "(library)", "(search)"]) {
      expect(firstScreen(tab)).toBe("index")
    }
  })
})

describe("the shared screens", () => {
  it("are in every tab's stack, and the account sheet is its own stack", () => {
    const root = appRoutes()
    const names = (tab: string) =>
      findGroup(root, tab)?.children.map((child) => child.route)
    const shared = [
      "show/[id]",
      "episode/[id]",
      "preview",
      "show-settings/[id]",
      "downloads",
      "playlist/[id]",
      "playlist-edit/[id]",
      "history",
      "bookmarks",
      "up-next",
      "saved",
      "latest",
      "shows",
      "arrange",
      "category/[id]",
    ]
    for (const tab of ["(home)", "(new)", "(library)", "(search)"]) {
      expect(names(tab)).toEqual(expect.arrayContaining(shared))
    }
    expect(findGroup(root, "account")?.children.map((c) => c.route)).toEqual(
      expect.arrayContaining(["index", "stats"]),
    )
  })
})
