// LOFI-FORK: reading and writing a book's lofi score inside its read-aloud
// EPUB, for the lofi-score route (see FORK.md). Kept apart from the route so
// it can be tested without the server's auth.
import { mkdir, writeFile } from "node:fs/promises"
import { dirname, join } from "node:path"
import { type Readable } from "node:stream"

import { type Entry, open as openZip, type ZipFile } from "yauzl"

import { Epub } from "@storyteller-platform/epub"

/** Where the score sits inside the EPUB; the phone looks there first. */
export const SCORE_PATH = "META-INF/storyteller-lofi/score.json"
export const SCORE_FORMAT = 1

function openZipFile(path: string): Promise<ZipFile> {
  return new Promise((resolvePromise, reject) => {
    openZip(path, { lazyEntries: true, autoClose: false }, (error, zipfile) => {
      if (error) reject(error)
      else resolvePromise(zipfile)
    })
  })
}

/** The entry at `fileName`, read without unpacking the rest of the archive. */
function findEntry(zipfile: ZipFile, fileName: string): Promise<Entry | null> {
  return new Promise((resolvePromise, reject) => {
    zipfile.on("entry", (entry: Entry) => {
      if (entry.fileName === fileName) resolvePromise(entry)
      else zipfile.readEntry()
    })
    zipfile.on("end", () => {
      resolvePromise(null)
    })
    zipfile.on("error", reject)
    zipfile.readEntry()
  })
}

function openEntryStream(zipfile: ZipFile, entry: Entry): Promise<Readable> {
  return new Promise((resolvePromise, reject) => {
    zipfile.openReadStream(entry, (error, readable) => {
      if (error) reject(error)
      else resolvePromise(readable)
    })
  })
}

async function readAll(readable: Readable): Promise<Buffer> {
  const chunks: Buffer[] = []
  for await (const chunk of readable) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as string))
  }
  return Buffer.concat(chunks)
}

/** The score inside the EPUB at `filepath`, or null when it has none. */
export async function readScore(filepath: string): Promise<Buffer | null> {
  const zipfile = await openZipFile(filepath)
  try {
    const entry = await findEntry(zipfile, SCORE_PATH)
    if (!entry) return null
    return await readAll(await openEntryStream(zipfile, entry))
  } finally {
    zipfile.close()
  }
}

type ScoreShape = { mood: boolean; atmosphere: boolean }

/** What a score holds, or null when the text is not a format 1 score. */
export function describeScore(text: string): ScoreShape | null {
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    return null
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return null
  const score = parsed as Record<string, unknown>
  if (score["format"] !== SCORE_FORMAT) return null
  const isPart = (part: unknown) =>
    !!part && typeof part === "object" && !Array.isArray(part)
  const shape = {
    mood: isPart(score["mood"]),
    atmosphere: isPart(score["atmosphere"]),
  }
  return shape.mood || shape.atmosphere ? shape : null
}

/** Puts the score inside the EPUB at `filepath`, replacing one already there. */
export async function writeScore(filepath: string, text: string) {
  using epub = await Epub.from(filepath)
  const root = epub.adapterRootPath
  if (!root) throw new Error("the EPUB was not unpacked on disk")
  const target = join(root, SCORE_PATH)
  await mkdir(dirname(target), { recursive: true })
  await writeFile(target, text, "utf-8")
  await epub.saveAndClose()
}
