// LOFI-FORK: the podcasts section's player (see FORK.md).
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs"
import { join, resolve } from "node:path"

import { describe, expect, it } from "vitest"

describe("who may open the player", () => {
  const ROOT = resolve(__dirname, "../..")

  function sources(folder: string): string[] {
    const dir = join(ROOT, folder)
    if (!existsSync(dir)) return []
    return readdirSync(dir).flatMap((name) => {
      const path = join(dir, name)
      if (statSync(path).isDirectory()) return sources(join(folder, name))
      return /\.tsx?$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : []
    })
  }

  function read(file: string) {
    return readFileSync(join(ROOT, file), "utf8")
  }

  it("only the gate pushes the player route", () => {
    const files = [
      ...sources("podcasts"),
      ...sources("modules/podcasts"),
      ...sources("app/(root)/podcasts"),
    ]
    const offenders = files.filter(
      (file) =>
        !file.endsWith(join("modules", "podcasts", "playerGate.ts")) &&
        /\/podcasts\/player["'`]/.test(readFileSync(file, "utf8")),
    )
    expect(offenders).toEqual([])
  })

  it("the layout makes the player screen singular, so copies cannot stack", () => {
    const layout = read("app/(root)/podcasts/_layout.tsx")
    expect(layout).toMatch(
      /<Stack\.Screen[^>]*name="player"[^>]*dangerouslySingular/s,
    )
  })

  it("the player screen reports to the gate and closes through it", () => {
    const screen = read("podcasts/PlayerScreen.tsx")
    expect(screen).toContain("playerShown()")
    expect(screen).toContain("playerGone()")
    expect(screen).toContain("closePlayer(router)")
    expect(screen).not.toContain("router.back(")
    expect(screen).toContain('testID="podcasts-player"')
    expect(screen).toContain('testID="podcasts-player-close"')
  })

  it("the mini player opens through the gate and reads the player in pieces", () => {
    const mini = read("podcasts/MiniPlayer.tsx")
    expect(mini).toContain("openPlayer(router)")
    expect(mini).not.toMatch(/\busePlayer\(/)
    expect(mini).toContain('testID="podcasts-mini-player"')
    expect(mini).toContain("active:opacity-60")
  })
})
