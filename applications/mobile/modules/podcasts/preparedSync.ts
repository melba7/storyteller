// LOFI-FORK: the podcasts section's prepared copies from the Mac (see FORK.md).
//
// The Mac prepares new episodes and puts the audio it marked in `Podcasts/prepared/` of the linked
// folder; `ahead-ads.json` says which file is which episode's (docs/PLAN.md, "Prepared episodes").
// On Wi-Fi the phone asks the native side which copies to take (`preparedPlan`: the episodes of
// its list of next episodes and the ones it has downloaded and not started), copies each from the
// folder into a temporary file, has the native side check and install it, and removes the copies
// that were taken only for the list and are not on it any more. A copy iCloud has not brought yet
// is left for the next run; a copy that fails or is refused does not stop the others. Everything
// that touches the phone is passed in (`PreparedDeps`), so this file has no native import and the
// run is tested; preparedRun.ts wires it to the database and the native modules.
import type { LinkedFileCopy } from "@/modules/lofi-score"

import type { PreparedInstallAnswer } from "./index"
import { isLocalEpisodeId } from "./localFiles"

/** Where the Mac's copies are, below `Podcasts/` of the linked folder. */
export const PREPARED_FOLDER = "prepared"

/** One episode the Mac may have prepared, as the native plan is asked about it. */
export type PreparedCandidate = {
  id: string
  /** The episode's audio address, kept as the download's address when it has none. */
  address: string
  /** Its place on the phone's list of next episodes, counted from 0, or null when it is not there. */
  listPlace: number | null
  /** A saved position above zero, or played: its position and ads stay on the file it was started on. */
  started: boolean
  showId: string
}

/** A copy the plan says to take. */
export type PreparedTake = {
  id: string
  /** `prepared/<name>`, below `Podcasts/`. */
  file: string
  sha256: string
  bytes: number
  fileExtension: string
}

export type PreparedPlan = { take: PreparedTake[]; giveBack: string[] }

/** What one run did, by episode id. */
export type PreparedReport = {
  installed: string[]
  /** iCloud was asked for the file; the next run asks again. */
  waiting: string[]
  /** The episode was in the player or being downloaded: the next run tries again. */
  busy: string[]
  /** The native side refused the file, with its one word. Not copied again in this launch. */
  refused: Record<string, string>
  failed: string[]
  gaveBack: string[]
}

export type PreparedDeps = {
  hasLinkedFolder(): Promise<boolean>
  /** Whether the phone is on Wi-Fi, by the rule automatic downloads use. */
  onWiFi(): Promise<boolean>
  candidates(): Promise<PreparedCandidate[]>
  /** `Podcasts.preparedPlan`: the candidates as JSON text in, the plan as JSON text out. */
  plan(candidatesJson: string): Promise<string>
  /** `LofiScore.copyLinkedFolderFile`. */
  copy(path: string, to: string): Promise<LinkedFileCopy>
  install(
    episodeId: string,
    uri: string,
    address: string,
    forListOnly: boolean,
  ): Promise<PreparedInstallAnswer>
  giveBack(episodeId: string): Promise<boolean>
  /** Where the copy of this take is put for the native side to read. */
  tempFile(take: PreparedTake): string
  removeFile(uri: string): Promise<void>
  /** Removes what an earlier run left in the temporary place. */
  clearTemp(): Promise<void>
  /** The clock, in milliseconds. */
  now(): number
  /** Runs `run` once, `ms` milliseconds from now. */
  later(ms: number, run: () => Promise<void>): void
}

/** No copy is started once a run has been going this long (milliseconds). */
export const START_BUDGET_MS = 20_000

/** When a run left a copy waiting, one more pass runs this long after it (milliseconds). */
export const SECOND_PASS_MS = 45_000

// MARK: The candidates

/** What `preparedCandidates` needs of an episode of the library. */
export type PreparedEpisode = {
  id: string
  address: string
  showId: string
  positionSeconds: number
  played: boolean
}

function isWebAddress(address: string): boolean {
  return /^https?:\/\/\S+/i.test(address)
}

/**
 * The candidates: the phone's list of next episodes in its order (its place is the index), then
 * the downloaded episodes that are not on it. An episode named twice stays at its first place. An
 * added file and an episode with no web address are left out: the Mac prepares neither.
 */
export function preparedCandidates(
  listed: readonly PreparedEpisode[],
  downloaded: readonly PreparedEpisode[],
): PreparedCandidate[] {
  const found: PreparedCandidate[] = []
  const seen = new Set<string>()
  const add = (episode: PreparedEpisode, listPlace: number | null) => {
    if (seen.has(episode.id)) return
    if (isLocalEpisodeId(episode.id) || !isWebAddress(episode.address)) return
    seen.add(episode.id)
    found.push({
      id: episode.id,
      address: episode.address,
      listPlace,
      started: episode.positionSeconds > 0 || episode.played,
      showId: episode.showId,
    })
  }
  listed.forEach((episode, place) => add(episode, place))
  for (const episode of downloaded) add(episode, null)
  return found
}

/** The text the native plan reads; a place that is null is left out. */
export function candidatesJson(
  candidates: readonly PreparedCandidate[],
): string {
  return JSON.stringify(
    candidates.map((one) => ({
      id: one.id,
      ...(one.listPlace === null ? {} : { listPlace: one.listPlace }),
      started: one.started,
      showId: one.showId,
    })),
  )
}

// MARK: The plan

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

/** `prepared/<one plain name>`: no folder above it, no hidden name. */
function isPreparedFile(file: string): boolean {
  const name = file.slice(PREPARED_FOLDER.length + 1)
  return (
    file.startsWith(`${PREPARED_FOLDER}/`) &&
    name !== "" &&
    !name.startsWith(".") &&
    !/[/\\]/.test(name) &&
    !name.includes("..")
  )
}

function readTake(value: unknown): PreparedTake | null {
  if (!isRecord(value)) return null
  const { id, file, sha256, bytes, fileExtension } = value
  if (typeof id !== "string" || id === "") return null
  if (typeof file !== "string" || !isPreparedFile(file)) return null
  if (typeof sha256 !== "string" || !/^[0-9a-f]{64}$/.test(sha256)) return null
  if (typeof bytes !== "number" || !Number.isFinite(bytes) || bytes <= 0)
    return null
  if (
    typeof fileExtension !== "string" ||
    !/^[a-z0-9]{1,5}$/.test(fileExtension)
  )
    return null
  return { id, file, sha256, bytes, fileExtension }
}

/** The plan the native side answered. Text it cannot read is a plan with nothing to do. */
export function parsePreparedPlan(text: string): PreparedPlan {
  const nothing: PreparedPlan = { take: [], giveBack: [] }
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return nothing
  }
  if (!isRecord(value)) return nothing
  const take = Array.isArray(value["take"])
    ? (value["take"] as unknown[]).flatMap((one) => readTake(one) ?? [])
    : []
  const giveBack = Array.isArray(value["giveBack"])
    ? (value["giveBack"] as unknown[]).filter(
        (id): id is string => typeof id === "string" && id !== "",
      )
    : []
  return { take, giveBack }
}

// MARK: The run

/** The answers that say the file is not the Mac's copy: the same file is not copied again. */
const ABOUT_THE_FILE: readonly PreparedInstallAnswer[] = [
  "noCopy",
  "size",
  "hash",
  "unreadable",
]

/**
 * One run. Does nothing without a linked folder or off Wi-Fi. `refused` maps an episode to the
 * SHA-256 of the file the native side refused, so that file is not copied again until the Mac
 * lists another one (it is kept for the launch). Never throws: a part that fails is told in the
 * log and the rest goes on. No copy is started after `START_BUDGET_MS`; asking iCloud for a
 * waiting copy costs nothing, so the plan is gone through and a waiting copy is simply left. When
 * a copy was left waiting, one more pass runs `SECOND_PASS_MS` later (`again` is false for that
 * pass, which schedules nothing).
 */
export async function syncPrepared(
  deps: PreparedDeps,
  refused: Map<string, string> = new Map(),
  again = true,
): Promise<PreparedReport> {
  const began = deps.now()
  const report: PreparedReport = {
    installed: [],
    waiting: [],
    busy: [],
    refused: {},
    failed: [],
    gaveBack: [],
  }
  try {
    if (!(await deps.hasLinkedFolder()) || !(await deps.onWiFi())) return report
    await deps.clearTemp()
    const candidates = await deps.candidates()
    if (candidates.length === 0) return report
    const asked = new Map(candidates.map((one) => [one.id, one]))
    const plan = parsePreparedPlan(await deps.plan(candidatesJson(candidates)))
    for (const id of plan.giveBack) {
      try {
        if (await deps.giveBack(id)) report.gaveBack.push(id)
      } catch (cause) {
        console.warn("Couldn't give a prepared copy back", cause)
      }
    }
    for (const take of plan.take) {
      const episode = asked.get(take.id)
      if (!episode || refused.get(take.id) === take.sha256) continue
      if (deps.now() - began >= START_BUDGET_MS) break
      await takeOne(deps, take, episode, refused, report)
    }
    if (again && report.waiting.length > 0)
      deps.later(SECOND_PASS_MS, async () => {
        await syncPrepared(deps, refused, false)
      })
  } catch (cause) {
    console.warn("Couldn't take the Mac's prepared copies", cause)
  }
  return report
}

async function takeOne(
  deps: PreparedDeps,
  take: PreparedTake,
  episode: PreparedCandidate,
  refused: Map<string, string>,
  report: PreparedReport,
): Promise<void> {
  const to = deps.tempFile(take)
  try {
    const copied = await deps.copy(`Podcasts/${take.file}`, to)
    if (copied.status === "waiting") {
      report.waiting.push(take.id)
      return
    }
    if (copied.status !== "copied") {
      report.failed.push(take.id)
      return
    }
    const answer = await deps.install(
      take.id,
      to,
      episode.address,
      episode.listPlace !== null,
    )
    if (answer === "installed") {
      report.installed.push(take.id)
    } else if (answer === "playing" || answer === "downloading") {
      report.busy.push(take.id)
    } else if (ABOUT_THE_FILE.includes(answer)) {
      refused.set(take.id, take.sha256)
      report.refused[take.id] = answer
    } else {
      report.failed.push(take.id)
    }
  } catch (cause) {
    report.failed.push(take.id)
    console.warn(`Couldn't take the Mac's copy of ${take.id}`, cause)
  } finally {
    await deps.removeFile(to).catch(() => undefined)
  }
}
