import { describe, expect, it } from "vitest"

import {
  MAP_TRIES,
  type MapSource,
  fetchEpisodeMap,
  isMapPath,
  mapTryAgain,
} from "./episodeMap"

function source(
  over: Partial<MapSource> & { calls?: string[] } = {},
): MapSource & { calls: string[] } {
  const calls = over.calls ?? []
  return {
    calls,
    wanted: async (id) => {
      calls.push(`wanted ${id}`)
      return "maps/0123456789ab.json"
    },
    read: async (path) => {
      calls.push(`read ${path}`)
      return { status: "found", text: '{"version":1}' }
    },
    install: async (id, text) => {
      calls.push(`install ${id} ${text}`)
      return true
    },
    ...over,
  }
}

describe("fetchEpisodeMap", () => {
  it("reads the map the native side asks for from the Podcasts folder and installs it", async () => {
    const mac = source()
    expect(await fetchEpisodeMap("e1", mac)).toBe("installed")
    expect(mac.calls).toEqual([
      "wanted e1",
      "read Podcasts/maps/0123456789ab.json",
      'install e1 {"version":1}',
    ])
  })

  it("does nothing when no map is wanted", async () => {
    const mac = source({ wanted: async () => null })
    expect(await fetchEpisodeMap("e1", mac)).toBe("none")
    expect(mac.calls).toEqual([])
  })

  it("never reads a path that is not a plain map name", async () => {
    for (const path of [
      "maps/../ahead-ads.json",
      "prepared/abc.json",
      "maps/a/b.json",
      "maps/abc.mp3",
      "/maps/abc.json",
    ]) {
      const mac = source({ wanted: async () => path })
      expect(await fetchEpisodeMap("e1", mac)).toBe("none")
      expect(mac.calls).toEqual([])
    }
  })

  it("waits when iCloud has not brought the file yet, or does not list it yet", async () => {
    for (const status of ["notDownloaded", "missing"] as const) {
      const mac = source({ read: async () => ({ status }) })
      expect(await fetchEpisodeMap("e1", mac)).toBe("waiting")
      expect(mac.calls).toEqual(["wanted e1"])
    }
  })

  it("gives up for now when there is no linked folder or the file is not text", async () => {
    for (const read of [
      { status: "notLinked" } as const,
      { status: "folderGone" } as const,
      { status: "unreadable", message: "not text" } as const,
    ]) {
      const mac = source({ read: async () => read })
      expect(await fetchEpisodeMap("e1", mac)).toBe("none")
    }
  })

  it("says so when the native side refuses the file", async () => {
    const mac = source({ install: async () => false })
    expect(await fetchEpisodeMap("e1", mac)).toBe("refused")
  })
})

describe("isMapPath", () => {
  it("takes maps/<name>.json with one plain name", () => {
    expect(isMapPath("maps/0123456789ab.json")).toBe(true)
    expect(isMapPath("maps/.json")).toBe(false)
    expect(isMapPath("maps/..json")).toBe(false)
    expect(isMapPath("maps\\a.json")).toBe(false)
  })
})

describe("mapTryAgain", () => {
  it("tries again only while waiting, with tries left, for the episode still wanted", () => {
    expect(mapTryAgain("waiting", 1, true)).toBe(true)
    expect(mapTryAgain("waiting", MAP_TRIES - 1, true)).toBe(true)
    expect(mapTryAgain("waiting", MAP_TRIES, true)).toBe(false)
    expect(mapTryAgain("waiting", 1, false)).toBe(false)
    for (const done of ["none", "installed", "refused"] as const)
      expect(mapTryAgain(done, 1, true)).toBe(false)
  })
})
