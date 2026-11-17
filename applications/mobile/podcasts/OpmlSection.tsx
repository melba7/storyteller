// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useState } from "react"
import { ActivityIndicator, Alert, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { readableError } from "@/modules/podcasts/nativeError"
import { exportOpmlFile, importOpmlFile } from "@/modules/podcasts/opmlFiles"
import { progressLine, summaryLine } from "@/modules/podcasts/opmlImport"

import { ROW } from "./SettingsGroup"

/** How many failed shows are named before "and 3 more". */
const NAMED_FAILURES = 5

/** Profile's Import and Export buttons for your shows as an OPML file. */
export function OpmlSection() {
  const [progress, setProgress] = useState<string | null>(null)
  const [result, setResult] = useState<string | null>(null)

  async function importShows() {
    setResult(null)
    setProgress("Reading the file")
    try {
      const outcome = await importOpmlFile((done, total) =>
        setProgress(progressLine(done, total)),
      )
      if (outcome.kind === "cancelled") return
      const { summary } = outcome
      const named = summary.failed
        .slice(0, NAMED_FAILURES)
        .map((failure) => `${failure.title}: ${failure.reason}`)
      const more = summary.failed.length - named.length
      setResult(
        [
          summaryLine(summary),
          ...named,
          ...(more > 0 ? [`and ${more} more failed`] : []),
        ].join("\n"),
      )
    } catch (cause) {
      setResult(readableError(cause))
    } finally {
      setProgress(null)
    }
  }

  async function exportShows() {
    setResult(null)
    try {
      if ((await exportOpmlFile()) === 0) {
        Alert.alert("Nothing to export", "You don't follow any shows yet.")
      }
    } catch (cause) {
      Alert.alert("Couldn't export your shows", readableError(cause))
    }
  }

  const busy = progress !== null
  return (
    <View className={`${ROW} gap-2 py-3`}>
      <Text className="font-semibold">Your shows as a file</Text>
      <Text className="text-muted-foreground text-sm">
        An OPML file moves your shows to or from another podcast app.
      </Text>
      <View className="flex-row gap-2">
        <Button
          variant="outline"
          className="flex-1 rounded-full"
          disabled={busy}
          accessibilityLabel="Import shows from an OPML file"
          onPress={() => void importShows()}
        >
          <Text>Import</Text>
        </Button>
        <Button
          variant="outline"
          className="flex-1 rounded-full"
          disabled={busy}
          accessibilityLabel="Export your shows as an OPML file"
          onPress={() => void exportShows()}
        >
          <Text>Export</Text>
        </Button>
      </View>
      {progress === null ? null : (
        <View
          className="flex-row items-center gap-2"
          accessibilityLiveRegion="polite"
        >
          <ActivityIndicator accessibilityLabel="Importing" />
          <Text className="text-muted-foreground text-sm">{progress}</Text>
        </View>
      )}
      {result === null ? null : (
        <Text className="text-sm" accessibilityLiveRegion="polite">
          {result}
        </Text>
      )}
    </View>
  )
}
