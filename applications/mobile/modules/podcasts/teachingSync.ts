// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
//
// Reads `Podcasts/teaching.json` from the linked sounds folder, fetches the files whose
// checksum is not the installed one and hands each to the native side, which checks and installs
// it. A file iCloud has not brought yet is tried again at the next run. A file the native side
// refuses is not sent again in this launch until the list shows another checksum for it. Nothing
// on the phone is deleted because a file is missing. The rules are in
// teaching.ts. Not imported by any test, because the native modules are not there.
import { LofiScore } from "@/modules/lofi-score"

import { type AppleExport, parseAppleExport } from "./applePodcasts"
import { onLibraryChanged } from "./changes"
import { listShows } from "./db"
import { Podcasts } from "./index"
import {
  TEACHING_LIST_FILE,
  filesToFetch,
  parseTeachingList,
  parseTeachingState,
  showTableText,
} from "./teaching"

const APPLE_FILE = "Podcasts/apple-podcasts.json"
let sentShows: string | null = null
let watching = false
// The files the phone refused in this launch, by name, with the checksum that was refused.
const refused: Record<string, string> = {}

/** The Apple Podcasts export in the linked folder, or null when it is not there to read. */
async function appleExport(): Promise<AppleExport | null> {
  if (!LofiScore) return null
  try {
    const read = await LofiScore.readLinkedFolderFileStatus(APPLE_FILE)
    return read.status === "found" ? parseAppleExport(read.text) : null
  } catch {
    return null
  }
}

/** Tells the native side which feed is which show, when the followed shows are not as last told. */
export async function sendTeachingShows(): Promise<void> {
  if (!Podcasts) return
  const text = showTableText(await listShows(), await appleExport())
  if (text === sentShows) return
  await Podcasts.setTeachingShows(text)
  sentShows = text
}

/** Sends the table again whenever the followed shows change. Starts once. */
export function watchTeachingShows(): void {
  if (watching) return
  watching = true
  onLibraryChanged(() => {
    sendTeachingShows().catch((cause) =>
      console.warn(
        "Couldn't tell the phone which feeds are which shows",
        cause,
      ),
    )
  })
}

/** Fetches and installs the teaching files that are new. Never throws for a missing file. */
export async function syncTeaching(): Promise<void> {
  if (!Podcasts || !LofiScore) return
  const read = await LofiScore.readLinkedFolderFileStatus(TEACHING_LIST_FILE)
  if (read.status !== "found") return
  const list = parseTeachingList(read.text)
  if (list === null) return
  // The table goes first, so a file that names shows is converted the moment it is installed.
  await sendTeachingShows()
  const state = parseTeachingState(await Podcasts.getTeachingState())
  for (const name of filesToFetch(list, state.installed, refused)) {
    const listed = list[name]
    if (!listed) continue
    try {
      const file = await LofiScore.readLinkedFolderFileStatus(
        `Podcasts/${name}`,
      )
      if (file.status !== "found") continue
      const done = await Podcasts.installTeachingFile(
        name,
        file.text,
        listed.sha256,
      )
      if (!done) {
        refused[name] = listed.sha256
        console.warn(`The phone did not take ${name} from the Mac`)
      }
    } catch (cause) {
      console.warn(`Couldn't install ${name} from the Mac`, cause)
    }
  }
}
