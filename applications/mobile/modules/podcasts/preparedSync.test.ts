// LOFI-FORK: the podcasts section's prepared copies from the Mac (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LinkedFileCopy } from "@/modules/lofi-score"

import type { PreparedInstallAnswer } from "./index"
import {
  type PreparedCandidate,
  type PreparedDeps,
  type PreparedTake,
  PREPARED_FOLDER,
  SECOND_PASS_MS,
  START_BUDGET_MS,
  candidatesJson,
  parsePreparedPlan,
  preparedCandidates,
  singleRun,
  syncPrepared,
} from "./preparedSync"

const hashA = "a".repeat(64)
const hashB = "b".repeat(64)

const take = (id: string, sha256 = hashA): PreparedTake => ({
  id,
  file: `prepared/${id}.mp3`,
  sha256,
  bytes: 1000,
  fileExtension: "mp3",
})

const candidate = (
  id: string,
  extra: Partial<PreparedCandidate> = {},
): PreparedCandidate => ({
  id,
  address: `https://audio.example.com/${id}.mp3`,
  listPlace: null,
  stillListed: false,
  started: false,
  showId: "show-1",
  ...extra,
})

/** A phone with everything in order. Every call is noted in `calls`. */
function phone(
  options: {
    linked?: boolean
    wifi?: boolean
    candidates?: PreparedCandidate[]
    plan?: { take?: PreparedTake[]; giveBack?: string[] }
    copy?: (path: string) => LinkedFileCopy | Promise<LinkedFileCopy>
    install?: (
      id: string,
    ) => PreparedInstallAnswer | Promise<PreparedInstallAnswer>
    giveBack?: (id: string) => boolean | Promise<boolean>
    /** Whether the episode was started when it is looked at again, just before the install. */
    started?: (id: string) => boolean | Promise<boolean>
    /** How long each copy takes on the clock, in milliseconds. */
    copyMs?: number
  } = {},
) {
  const clock = { now: 1_000_000 }
  const later: { ms: number; run: () => Promise<void> }[] = []
  const calls: string[] = []
  const planned: string[] = []
  const installs: {
    id: string
    uri: string
    address: string
    forListOnly: boolean
  }[] = []
  const files = new Set<string>()
  const deps: PreparedDeps = {
    hasLinkedFolder: async () => {
      calls.push("linked")
      return options.linked ?? true
    },
    onWiFi: async () => {
      calls.push("wifi")
      return options.wifi ?? true
    },
    candidates: async () => {
      calls.push("candidates")
      return options.candidates ?? [candidate("e1", { listPlace: 0 })]
    },
    plan: async (json) => {
      calls.push("plan")
      planned.push(json)
      return JSON.stringify({
        take: options.plan?.take ?? [],
        giveBack: options.plan?.giveBack ?? [],
      })
    },
    copy: async (path, to) => {
      calls.push(`copy ${path}`)
      clock.now += options.copyMs ?? 0
      files.add(to)
      return (await options.copy?.(path)) ?? { status: "copied", bytes: 1000 }
    },
    install: async (id, uri, address, forListOnly) => {
      calls.push(`install ${id}`)
      installs.push({ id, uri, address, forListOnly })
      return (await options.install?.(id)) ?? "installed"
    },
    giveBack: async (id) => {
      calls.push(`giveBack ${id}`)
      return (await options.giveBack?.(id)) ?? true
    },
    hasStarted: async (id) => {
      calls.push(`started? ${id}`)
      return (await options.started?.(id)) ?? false
    },
    tempFile: (one) =>
      `file:///cache/prepared-copies/${one.id}.${one.fileExtension}`,
    removeFile: async (uri) => {
      calls.push(`remove ${uri}`)
      files.delete(uri)
    },
    clearTemp: async () => {
      calls.push("clearTemp")
      files.clear()
    },
    now: () => clock.now,
    later: (ms, run) => {
      later.push({ ms, run })
    },
  }
  return { deps, calls, planned, installs, files, later }
}

describe("syncPrepared: when it runs", () => {
  it("does nothing without a linked folder", async () => {
    const run = phone({ linked: false, plan: { take: [take("e1")] } })
    const report = await syncPrepared(run.deps)
    expect(run.calls).toEqual(["linked"])
    expect(report.installed).toEqual([])
  })

  it("does nothing off Wi-Fi", async () => {
    const run = phone({ wifi: false, plan: { take: [take("e1")] } })
    await syncPrepared(run.deps)
    expect(run.calls).toEqual(["linked", "wifi"])
  })

  it("asks the plan for nothing when there are no candidates", async () => {
    const run = phone({ candidates: [] })
    await syncPrepared(run.deps)
    expect(run.planned).toEqual([])
  })

  it("never throws: a failing read is a quiet run", async () => {
    const run = phone()
    run.deps.candidates = async () => {
      throw new Error("no database")
    }
    await expect(syncPrepared(run.deps)).resolves.toBeDefined()
  })
})

describe("syncPrepared: taking copies", () => {
  it("copies each file of the plan from the folder and installs it", async () => {
    const run = phone({
      candidates: [
        candidate("e1", { listPlace: 0 }),
        candidate("e2", { listPlace: null }),
      ],
      plan: { take: [take("e1"), take("e2")] },
    })
    const report = await syncPrepared(run.deps)
    expect(run.calls).toContain(`copy Podcasts/${PREPARED_FOLDER}/e1.mp3`)
    expect(run.calls).toContain(`copy Podcasts/${PREPARED_FOLDER}/e2.mp3`)
    expect(report.installed).toEqual(["e1", "e2"])
    expect(run.installs).toEqual([
      {
        id: "e1",
        uri: "file:///cache/prepared-copies/e1.mp3",
        address: "https://audio.example.com/e1.mp3",
        // On the list and taken for it.
        forListOnly: true,
      },
      {
        id: "e2",
        uri: "file:///cache/prepared-copies/e2.mp3",
        address: "https://audio.example.com/e2.mp3",
        // A download of the listener's own, off the list.
        forListOnly: false,
      },
    ])
  })

  it("leaves a copy that iCloud is still bringing for the next run", async () => {
    let answer: LinkedFileCopy = { status: "waiting" }
    const run = phone({
      plan: { take: [take("e1")] },
      copy: () => answer,
    })
    const first = await syncPrepared(run.deps)
    expect(first.waiting).toEqual(["e1"])
    expect(first.installed).toEqual([])
    expect(run.installs).toEqual([])

    answer = { status: "copied", bytes: 1000 }
    const second = await syncPrepared(run.deps)
    expect(second.installed).toEqual(["e1"])
    expect(run.installs.map((one) => one.id)).toEqual(["e1"])
  })

  it("does not stop at a copy that fails or one that is refused", async () => {
    const run = phone({
      candidates: [
        candidate("e1", { listPlace: 0 }),
        candidate("e2", { listPlace: 1 }),
        candidate("e3", { listPlace: 2 }),
        candidate("e4", { listPlace: 3 }),
      ],
      plan: { take: [take("e1"), take("e2"), take("e3"), take("e4")] },
      copy: (path) => {
        if (path.endsWith("e1.mp3")) throw new Error("the folder went away")
        return { status: "copied", bytes: 1000 }
      },
      install: (id) => {
        if (id === "e2") return "hash"
        if (id === "e3") throw new Error("the native side failed")
        return "installed"
      },
    })
    const report = await syncPrepared(run.deps)
    expect(report.installed).toEqual(["e4"])
    expect(report.refused).toEqual({ e2: "hash" })
    expect(report.failed.sort()).toEqual(["e1", "e3"])
    expect(run.calls).toContain("install e4")
  })

  it("says missing and unreadable files as failures and goes on", async () => {
    const run = phone({
      candidates: [
        candidate("e1", { listPlace: 0 }),
        candidate("e2", { listPlace: 1 }),
      ],
      plan: { take: [take("e1"), take("e2")] },
      copy: (path) =>
        path.endsWith("e1.mp3")
          ? { status: "missing" }
          : { status: "unreadable", message: "no room" },
    })
    const report = await syncPrepared(run.deps)
    expect(report.failed.sort()).toEqual(["e1", "e2"])
    expect(run.installs).toEqual([])
  })

  it("removes every temporary file, whatever happened to it", async () => {
    const run = phone({
      candidates: [
        candidate("e1", { listPlace: 0 }),
        candidate("e2", { listPlace: 1 }),
        candidate("e3", { listPlace: 2 }),
        candidate("e4", { listPlace: 3 }),
      ],
      plan: { take: [take("e1"), take("e2"), take("e3"), take("e4")] },
      copy: (path) => {
        if (path.endsWith("e1.mp3")) throw new Error("copy failed half way")
        if (path.endsWith("e2.mp3")) return { status: "waiting" }
        return { status: "copied", bytes: 1000 }
      },
      install: (id) => {
        if (id === "e3") throw new Error("install failed")
        return "installed"
      },
    })
    await syncPrepared(run.deps)
    expect(run.files.size).toBe(0)
    for (const id of ["e1", "e2", "e3", "e4"])
      expect(run.calls).toContain(
        `remove file:///cache/prepared-copies/${id}.mp3`,
      )
  })

  it("clears what an earlier run left behind before it starts", async () => {
    const run = phone()
    await syncPrepared(run.deps)
    expect(run.calls.indexOf("clearTemp")).toBeGreaterThan(-1)
    expect(run.calls.indexOf("clearTemp")).toBeLessThan(
      run.calls.indexOf("candidates"),
    )
  })

  it("does not take a candidate it did not ask about, or an unsafe path", async () => {
    const run = phone({
      candidates: [candidate("e1", { listPlace: 0 })],
      plan: {
        take: [
          take("e1"),
          take("stranger"),
          { ...take("e1"), file: "prepared/../../secret.mp3" },
          { ...take("e1"), file: "elsewhere/e1.mp3" },
        ],
      },
    })
    await syncPrepared(run.deps)
    expect(run.calls.filter((call) => call.startsWith("copy "))).toEqual([
      `copy Podcasts/prepared/e1.mp3`,
    ])
  })
})

describe("syncPrepared: the time it takes", () => {
  const six = Array.from({ length: 6 }, (_, n) => `e${n}`)
  const many = () =>
    phone({
      candidates: six.map((id, n) => candidate(id, { listPlace: n })),
      plan: { take: six.map((id) => take(id)) },
      copyMs: 8_000,
    })
  const copies = (calls: string[]) =>
    calls.filter((call) => call.startsWith("copy ")).length

  it("starts no copy once the budget has passed since the run began", async () => {
    const run = many()
    const report = await syncPrepared(run.deps)
    // Copies start at 0, 8 and 16 seconds; the one due at 24 seconds is not started.
    expect(START_BUDGET_MS).toBe(20_000)
    expect(copies(run.calls)).toBe(3)
    expect(report.installed).toEqual(["e0", "e1", "e2"])
  })

  it("starts every copy when each is quick", async () => {
    const run = phone({
      candidates: six.map((id, n) => candidate(id, { listPlace: n })),
      plan: { take: six.map((id) => take(id)) },
    })
    await syncPrepared(run.deps)
    expect(copies(run.calls)).toBe(6)
  })

  it("leaves a waiting copy and goes on to the next at once", async () => {
    const run = phone({
      candidates: six.map((id, n) => candidate(id, { listPlace: n })),
      plan: { take: six.map((id) => take(id)) },
      copy: (path) =>
        path.endsWith("e0.mp3")
          ? { status: "waiting" }
          : { status: "copied", bytes: 1 },
    })
    const report = await syncPrepared(run.deps)
    expect(report.waiting).toEqual(["e0"])
    expect(report.installed).toHaveLength(5)
  })

  it("runs one more pass 45 seconds later when a copy was waiting, and only one", async () => {
    const run = phone({
      plan: { take: [take("e1")] },
      copy: () => ({ status: "waiting" }),
    })
    await syncPrepared(run.deps)
    expect(run.later).toHaveLength(1)
    expect(run.later[0]?.ms).toBe(SECOND_PASS_MS)
    expect(SECOND_PASS_MS).toBe(45_000)
    expect(copies(run.calls)).toBe(1)

    // The second pass asks again, and it schedules nothing, even if the copy still waits.
    await run.later[0]?.run()
    expect(copies(run.calls)).toBe(2)
    expect(run.later).toHaveLength(1)
  })

  it("does not run a second pass when nothing was waiting", async () => {
    const run = phone({ plan: { take: [take("e1")] } })
    await syncPrepared(run.deps)
    expect(run.later).toEqual([])
  })

  it("does not run a second pass off Wi-Fi or without a folder", async () => {
    const off = phone({ wifi: false })
    await syncPrepared(off.deps)
    expect(off.later).toEqual([])
  })
})

describe("syncPrepared: an episode started while its copy came", () => {
  it("is not swapped: no install, no refusal, the temporary file removed", async () => {
    const refused = new Map<string, string>()
    const run = phone({
      plan: { take: [take("e1")] },
      started: () => true,
    })
    const report = await syncPrepared(run.deps, refused)
    expect(run.calls).toContain("started? e1")
    expect(run.installs).toEqual([])
    expect(report.started).toEqual(["e1"])
    expect(report.refused).toEqual({})
    expect(refused.size).toBe(0)
    expect(run.files.size).toBe(0)
    expect(run.calls).toContain("remove file:///cache/prepared-copies/e1.mp3")
  })

  it("is looked at after the copy, not before", async () => {
    const run = phone({ plan: { take: [take("e1")] } })
    await syncPrepared(run.deps)
    expect(run.calls.indexOf("started? e1")).toBeGreaterThan(
      run.calls.findIndex((call) => call.startsWith("copy ")),
    )
  })
})

describe("singleRun", () => {
  it("lets a second call during a pending first copy nothing and refuse nothing", async () => {
    const guard = singleRun()
    let release: () => void = () => undefined
    const first = phone({
      plan: { take: [take("e1")] },
      copy: () =>
        new Promise((resolve) => {
          release = () => resolve({ status: "copied", bytes: 1 })
        }),
    })
    const second = phone({ plan: { take: [take("e1")] } })
    const refused = new Map<string, string>()
    const pending = guard(() => syncPrepared(first.deps, refused))
    await new Promise((resolve) => setTimeout(resolve, 0))
    const skipped = await guard(() => syncPrepared(second.deps, refused))
    expect(skipped).toBeNull()
    expect(second.calls).toEqual([])
    expect(refused.size).toBe(0)
    release()
    await pending
    expect(first.installs.map((one) => one.id)).toEqual(["e1"])
    // Once the first is over, the next call runs.
    expect(await guard(() => syncPrepared(second.deps, refused))).not.toBeNull()
  })

  it("runs again after a run that threw", async () => {
    const guard = singleRun()
    await expect(
      guard(async () => {
        throw new Error("boom")
      }),
    ).rejects.toThrow("boom")
    expect(await guard(async () => 1)).toBe(1)
  })
})

describe("syncPrepared: refused copies", () => {
  it("does not copy the same refused file again in this launch", async () => {
    const refused = new Map<string, string>()
    const run = phone({
      plan: { take: [take("e1", hashA)] },
      install: () => "hash",
    })
    await syncPrepared(run.deps, refused)
    await syncPrepared(run.deps, refused)
    expect(run.calls.filter((call) => call.startsWith("copy "))).toHaveLength(1)
  })

  it("copies it again when the Mac lists another file for the episode", async () => {
    const refused = new Map<string, string>()
    const run = phone({ install: () => "size" })
    run.deps.plan = async () =>
      JSON.stringify({
        take: [take("e1", refused.size === 0 ? hashA : hashB)],
        giveBack: [],
      })
    await syncPrepared(run.deps, refused)
    await syncPrepared(run.deps, refused)
    expect(run.calls.filter((call) => call.startsWith("copy "))).toHaveLength(2)
  })

  it("asks again after an answer that is not about the file", async () => {
    for (const answer of ["playing", "downloading"] as const) {
      const refused = new Map<string, string>()
      const run = phone({
        plan: { take: [take("e1")] },
        install: () => answer,
      })
      await syncPrepared(run.deps, refused)
      await syncPrepared(run.deps, refused)
      expect(run.calls.filter((call) => call.startsWith("copy "))).toHaveLength(
        2,
      )
    }
  })
})

describe("syncPrepared: giving copies back", () => {
  it("gives back each copy the plan names, and a failure does not stop the others", async () => {
    const run = phone({
      plan: { giveBack: ["e1", "e2", "e3"] },
      giveBack: (id) => {
        if (id === "e2") throw new Error("busy")
        return id !== "e3"
      },
    })
    const report = await syncPrepared(run.deps)
    expect(run.calls.filter((call) => call.startsWith("giveBack "))).toEqual([
      "giveBack e1",
      "giveBack e2",
      "giveBack e3",
    ])
    expect(report.gaveBack).toEqual(["e1"])
  })

  it("gives back and takes in the same run", async () => {
    const run = phone({
      plan: { take: [take("e1")], giveBack: ["old"] },
    })
    const report = await syncPrepared(run.deps)
    expect(report.gaveBack).toEqual(["old"])
    expect(report.installed).toEqual(["e1"])
  })
})

describe("what the native plan is asked", () => {
  it("is JSON of the candidates, the list's place left out for an episode not on it", () => {
    const text = candidatesJson([
      candidate("e1", { listPlace: 0 }),
      candidate("e2", { started: true }),
    ])
    expect(JSON.parse(text)).toEqual([
      {
        id: "e1",
        listPlace: 0,
        stillListed: false,
        started: false,
        showId: "show-1",
      },
      { id: "e2", stillListed: false, started: true, showId: "show-1" },
    ])
  })
})

describe("parsePreparedPlan", () => {
  it("reads the answer", () => {
    expect(
      parsePreparedPlan(
        JSON.stringify({ take: [take("e1")], giveBack: ["e2"] }),
      ),
    ).toEqual({ take: [take("e1")], giveBack: ["e2"] })
  })

  it("reads an answer it cannot understand as nothing to do", () => {
    const nothing = { take: [], giveBack: [] }
    expect(parsePreparedPlan("")).toEqual(nothing)
    expect(parsePreparedPlan("[]")).toEqual(nothing)
    expect(parsePreparedPlan('{"take":5,"giveBack":"x"}')).toEqual(nothing)
  })

  it("leaves out entries that are not what the native side writes", () => {
    const plan = parsePreparedPlan(
      JSON.stringify({
        take: [
          take("good"),
          { id: "no-file" },
          { ...take("bad-ext"), fileExtension: "" },
          { ...take("bad-bytes"), bytes: "many" },
        ],
        giveBack: ["fine", 7, ""],
      }),
    )
    expect(plan.take.map((one) => one.id)).toEqual(["good"])
    expect(plan.giveBack).toEqual(["fine"])
  })
})

describe("preparedCandidates", () => {
  const facts = (
    id: string,
    extra: Partial<{
      address: string
      showId: string
      positionSeconds: number
      played: boolean
    }> = {},
  ) => ({
    id,
    address: `https://audio.example.com/${id}.mp3`,
    showId: "show-1",
    positionSeconds: 0,
    played: false,
    ...extra,
  })

  it("puts the list first in its order, then the downloads", () => {
    const found = preparedCandidates(
      [facts("b"), facts("a")],
      [facts("c"), facts("a"), facts("d")],
    )
    expect(found.map((one) => [one.id, one.listPlace])).toEqual([
      ["b", 0],
      ["a", 1],
      ["c", null],
      ["d", null],
    ])
  })

  it("says an episode with a saved position, or a played one, was started", () => {
    const found = preparedCandidates(
      [facts("a", { positionSeconds: 12 }), facts("b", { played: true })],
      [facts("c"), facts("d", { positionSeconds: 0.5 })],
    )
    expect(found.map((one) => one.started)).toEqual([true, true, false, true])
  })

  it("keeps the first of an episode named twice, with the list's place", () => {
    const found = preparedCandidates(
      [facts("a")],
      [facts("a", { played: true })],
    )
    expect(found).toHaveLength(1)
    expect(found[0]?.listPlace).toBe(0)
  })

  it("says an episode past the places taken is still in the whole list", () => {
    const found = preparedCandidates(
      [facts("a")],
      [facts("b"), facts("c"), facts("d")],
      ["z", "b", "a"],
    )
    expect(
      found.map((one) => [one.id, one.listPlace, one.stillListed]),
    ).toEqual([
      ["a", 0, true],
      ["b", null, true],
      ["c", null, false],
      ["d", null, false],
    ])
  })

  it("leaves out an added file and an episode with no web address", () => {
    const found = preparedCandidates(
      [facts("file-1"), facts("a", { address: "" }), facts("b")],
      [facts("c", { address: "file:///x.mp3" })],
    )
    expect(found.map((one) => one.id)).toEqual(["b"])
  })
})
