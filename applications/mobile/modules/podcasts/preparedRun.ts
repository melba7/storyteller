// LOFI-FORK: the podcasts section's prepared copies from the Mac (see FORK.md).
//
// Wires `syncPrepared` (preparedSync.ts) to the database and the native modules: the phone's list
// of next episodes and the downloaded episodes become the candidates, the Mac's file is copied by
// LofiScore and installed by the podcasts module. Not imported by any test, because those are
// native; the rules and the run are in preparedSync.ts.
import * as FileSystem from "expo-file-system/legacy"

import { LofiScore } from "@/modules/lofi-score"

import { loadSettings } from "./automaticSettings"
import { getEpisode, listEpisodesByIds, rows } from "./db"
import { listDownloads } from "./downloadsNative"
import { Podcasts } from "./index"
import type { QueueEntry } from "./phoneQueue"
import {
  type PreparedEpisode,
  copiesInstalled,
  preparedCandidates,
  singleRun,
  syncPrepared,
} from "./preparedSync"
import { listUpNext } from "./upNextNative"

/** The guids go to the database a few at a time, well under SQLite's limit on placeholders. */
const CHUNK = 200

const tempFolder = () => `${FileSystem.cacheDirectory ?? ""}prepared-copies/`

/** One run at a time: the second pass 45 seconds later and a new run may not overlap one that is going. */
const exclusive = singleRun()

/** The files the native side refused in this launch, by episode, with the checksum refused. */
const refused = new Map<string, string>()

/** The episodes of the phone's list, in its order, as the library knows them. */
async function listedEpisodes(
  queue: readonly QueueEntry[],
): Promise<PreparedEpisode[]> {
  const found = new Map<string, PreparedEpisode>()
  const guids = [...new Set(queue.map((one) => one.guid))]
  for (let i = 0; i < guids.length; i += CHUNK) {
    const part = guids.slice(i, i + CHUNK)
    const marks = part.map(() => "?").join(", ")
    for (const row of await rows(
      `SELECT e.id, e.guid, e.audio_url, e.show_id, e.position_seconds, e.played, s.feed_url
       FROM episodes e JOIN shows s ON s.id = e.show_id WHERE e.guid IN (${marks})`,
      part,
    )) {
      found.set(`${String(row["feed_url"])}\n${String(row["guid"])}`, {
        id: String(row["id"]),
        address: String(row["audio_url"] ?? ""),
        showId: String(row["show_id"] ?? ""),
        positionSeconds: Number(row["position_seconds"] ?? 0),
        played: row["played"] === 1 || row["played"] === true,
      })
    }
  }
  return queue.flatMap((one) => found.get(`${one.feed}\n${one.guid}`) ?? [])
}

/** The episodes with a finished download. */
async function downloadedEpisodes(): Promise<PreparedEpisode[]> {
  const ids = (await listDownloads())
    .filter((info) => info.state === "downloaded")
    .map((info) => info.episodeId)
  return (await listEpisodesByIds(ids)).map((episode) => ({
    id: episode.id,
    address: episode.audioUrl,
    showId: episode.showId,
    positionSeconds: episode.positionSeconds,
    played: episode.played,
  }))
}

/**
 * Takes the Mac's prepared copies (on mobile data only the next 3, when the listener allows it) and gives back the ones taken only for the list. Never
 * throws. `readQueue` reads the phone's list of next episodes, as the run that called it shares it.
 * Gives back how many copies this run installed: 0 when none, when another run was going, and
 * on errors.
 */
export async function runPrepared(
  readQueue: () => Promise<QueueEntry[]>,
): Promise<number> {
  const podcasts = Podcasts
  const lofi = LofiScore
  if (!podcasts || !lofi) return 0
  try {
    const report = await exclusive(() =>
      syncPrepared(
        {
          hasLinkedFolder: async () =>
            (await lofi.getStatus()).folder.linkedFolder !== undefined,
          onWiFi: () => podcasts.isOnWiFi(),
          copiesOnMobileData: async () =>
            (await loadSettings()).copiesOnMobileData,
          candidates: async () => {
            const listed = await listedEpisodes(await readQueue())
            // The whole list: all of Up Next and the episodes of the phone's list.
            const whole = [
              ...(await listUpNext()).map((item) => item.id),
              ...listed.map((one) => one.id),
            ]
            return preparedCandidates(listed, await downloadedEpisodes(), whole)
          },
          hasStarted: async (id) => {
            const episode = await getEpisode(id)
            return (
              episode === null || episode.positionSeconds > 0 || episode.played
            )
          },
          plan: (candidates) => podcasts.preparedPlan(candidates),
          copy: (path, to) => lofi.copyLinkedFolderFile(path, to),
          install: (id, uri, address, forListOnly) =>
            podcasts.installPreparedCopy(id, uri, address, forListOnly),
          giveBack: (id) => podcasts.giveBackPreparedCopy(id),
          tempFile: (take) =>
            `${tempFolder()}${take.id.replace(/[^A-Za-z0-9_-]/g, "_")}.${take.fileExtension}`,
          removeFile: (uri) =>
            FileSystem.deleteAsync(uri, { idempotent: true }),
          now: () => Date.now(),
          later: (ms, run) => {
            setTimeout(() => {
              exclusive(run).catch((cause: unknown) =>
                console.warn("Couldn't take the Mac's prepared copies", cause),
              )
            }, ms)
          },
          clearTemp: async () => {
            await FileSystem.deleteAsync(tempFolder(), { idempotent: true })
            await FileSystem.makeDirectoryAsync(tempFolder(), {
              intermediates: true,
            })
          },
        },
        refused,
      ),
    )
    return copiesInstalled(report)
  } catch (cause) {
    console.warn("Couldn't take the Mac's prepared copies", cause)
    return 0
  }
}
