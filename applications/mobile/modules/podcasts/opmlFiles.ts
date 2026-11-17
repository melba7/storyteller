// LOFI-FORK: the podcasts section's OPML reading and writing (see FORK.md).
//
// Picking an OPML file and following its shows, and writing the followed shows to a file for
// the share sheet. Not imported by any test, because the database, the file picker and the
// share sheet are native; the file format and the rules are in opml.ts and opmlImport.ts.
import * as DocumentPicker from "expo-document-picker"
import * as FileSystem from "expo-file-system/legacy"
import * as Sharing from "expo-sharing"

import { listShows } from "./db"
import { subscribe } from "./dbFeeds"
import { OpmlError, parseOpml, writeOpml } from "./opml"
import { type ImportSummary, importFeeds } from "./opmlImport"

/** What an import found out before following anything. */
export type ImportOutcome =
  | { kind: "cancelled" }
  | { kind: "done"; summary: ImportSummary; ignored: number }

/**
 * Lets the listener pick an OPML file and follows the shows in it. Throws a message to show
 * for a file that cannot be read or is not OPML. Every file type is offered, because iOS has
 * no common type for .opml.
 */
export async function importOpmlFile(
  onProgress: (done: number, total: number) => void,
): Promise<ImportOutcome> {
  const picked = await DocumentPicker.getDocumentAsync({
    type: "*/*",
    copyToCacheDirectory: true,
  })
  const file = picked.canceled ? null : picked.assets[0]
  if (!file) return { kind: "cancelled" }
  let text: string
  try {
    text = await FileSystem.readAsStringAsync(file.uri)
  } catch {
    throw new OpmlError("The file couldn't be read.")
  }
  const { feeds, ignored } = parseOpml(text)
  const followed = (await listShows()).map((show) => show.feedUrl)
  const summary = await importFeeds(feeds, followed, subscribe, onProgress)
  return { kind: "done", summary, ignored }
}

/** Writes every followed show to an OPML file and opens the share sheet. Returns the count. */
export async function exportOpmlFile(): Promise<number> {
  const shows = await listShows()
  if (shows.length === 0) return 0
  if (!(await Sharing.isAvailableAsync())) {
    throw new Error("Sharing isn't available on this device.")
  }
  const uri = `${FileSystem.cacheDirectory ?? ""}podcasts.opml`
  await FileSystem.writeAsStringAsync(uri, writeOpml(shows, new Date()))
  await Sharing.shareAsync(uri, { dialogTitle: "Export your shows" })
  return shows.length
}
