// LOFI-FORK: the lofi music's section in Settings (see FORK.md).
import { FolderInput } from "lucide-react-native"
import { useState } from "react"
import { Modal, ScrollView, View } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { LofiScore } from "@/modules/lofi-score"
import {
  moodCounts,
  moodName,
  musicSourceLabel,
  plainCredits,
} from "@/modules/lofi-score/status"

import { LofiMusicControls } from "./LofiMusicControls"
import { useLofiMusic } from "./useLofiMusic"

export function LofiMusicSettings() {
  const music = useLofiMusic(2000)
  const [importing, setImporting] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [credits, setCredits] = useState<string | null>(null)
  const insets = useSafeAreaInsets()

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

  async function showCredits() {
    try {
      const text = await LofiScore?.getMusicCredits()
      setCredits(
        text
          ? plainCredits(text)
          : "This music folder came without a CREDITS.md file.",
      )
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error))
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
              accessibilityLabel="Show the music credits"
              variant="ghost"
              onPress={() => void showCredits()}
            >
              <Text>Music credits</Text>
            </Button>
          )}
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
      <Modal
        visible={credits !== null}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => {
          setCredits(null)
        }}
      >
        <View
          className="bg-background flex-1 px-6 pt-6"
          style={{ paddingBottom: insets.bottom + 16 }}
        >
          <ScrollView className="flex-1">
            <Text selectable className="text-sm">
              {credits}
            </Text>
          </ScrollView>
          <Button
            accessibilityLabel="Close the music credits"
            variant="secondary"
            onPress={() => {
              setCredits(null)
            }}
          >
            <Text>Close</Text>
          </Button>
        </View>
      </Modal>
    </View>
  )
}
