// LOFI-FORK: the lofi music's section in Settings (see FORK.md).
import { FolderInput } from "lucide-react-native"
import { useState } from "react"
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  moodCounts,
  moodName,
  musicSourceLabel,
} from "@/modules/lofi-score/status"

import { LofiMusicControls } from "./LofiMusicControls"
import { useLofiMusic } from "./useLofiMusic"

export function LofiMusicSettings() {
  const music = useLofiMusic(2000)
  const [importing, setImporting] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  if (!music.available) return null
  const { status } = music

  async function importFolder() {
    setImporting(true)
    setMessage(null)
    try {
      const summary = await music.importMusicFolder()
      if (summary) {
        const parts = [
          `Imported ${summary.tracks} tracks from “${summary.folderName}”.`,
        ]
        if (summary.moodTracks > 0) {
          parts.push(`${summary.moodTracks} book mood tracks.`)
        }
        if (summary.notDownloaded > 0) {
          parts.push(
            `${summary.notDownloaded} files were still in iCloud and were left out: open the folder in Files to download them, then import again.`,
          )
        }
        setMessage(parts.join(" "))
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setImporting(false)
    }
  }

  return (
    <View className="mt-8 w-full gap-4">
      <Text variant="h2">Lofi Music</Text>
      <Text variant="p" className="text-sm">
        Quiet lofi music under the narration of readaloud books, matched to the
        mood of the passage being read. It only ever follows what you have
        already heard, so it never gives away what comes next. Turn it on or off
        and change its volume from the music button in the player too.
      </Text>
      <LofiMusicControls music={music} />
      {status && (
        <View className="w-full gap-2">
          <Text maxFontSizeMultiplier={1.5} className="text-lg">
            Music library
          </Text>
          <Text variant="muted">{musicSourceLabel(status.library)}</Text>
          {status.library.tracks > 0 && (
            <Text variant="muted">{moodCounts(status.library)}</Text>
          )}
          <Button
            accessibilityLabel="Import a music folder"
            variant="secondary"
            disabled={importing}
            onPress={() => void importFolder()}
          >
            <Icon as={FolderInput} />
            <Text>{importing ? "Importing…" : "Import a music folder"}</Text>
          </Button>
          <Text variant="muted">
            Pick a folder with one subfolder per mood (
            {status.library.moods.map((mood) => moodName(mood.mood)).join(", ")}
            ), for example from iCloud Drive. The music is copied into the app.
          </Text>
          {status.library.source === "imported" && (
            <Button
              accessibilityLabel="Remove the imported music"
              variant="ghost"
              disabled={importing}
              onPress={() => void music.removeImportedMusic()}
            >
              <Text>Remove imported music</Text>
            </Button>
          )}
          {message && <Text className="text-sm">{message}</Text>}
          {status.lastError && (
            <Text variant="muted">Last problem: {status.lastError}</Text>
          )}
        </View>
      )}
    </View>
  )
}
