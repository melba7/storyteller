// LOFI-FORK: the atmosphere's section in Settings (see FORK.md).
import { FolderInput, FolderSync } from "lucide-react-native"
import { useState } from "react"
import { Modal, ScrollView, View } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import { LofiScore } from "@/modules/lofi-score"
import {
  atmosphereSourceLabel,
  linkedFolderLabel,
  plainCredits,
} from "@/modules/lofi-score/status"

import { LofiAtmosphereControls } from "./LofiAtmosphereControls"
import { useLofiAtmosphere } from "./useLofiAtmosphere"

export function LofiAtmosphereSettings() {
  const atmosphere = useLofiAtmosphere(2000)
  const [importing, setImporting] = useState(false)
  const [syncing, setSyncing] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [credits, setCredits] = useState<string | null>(null)
  const insets = useSafeAreaInsets()

  if (!atmosphere.available) return null
  const { status } = atmosphere

  async function importFolder() {
    setImporting(true)
    setMessage(null)
    try {
      const summary = await atmosphere.importSoundsFolder()
      if (summary) {
        const parts = [
          `Imported ${summary.recordings} ${summary.recordings === 1 ? "sound" : "sounds"} from “${summary.folderName}”.`,
        ]
        if (summary.scores > 0) {
          parts.push(
            `${summary.scores} book ${summary.scores === 1 ? "score" : "scores"}.`,
          )
        }
        if (summary.atmosphereTracks > 0) {
          parts.push(`${summary.atmosphereTracks} book atmosphere tracks.`)
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

  async function syncFolder() {
    setSyncing(true)
    setMessage(null)
    try {
      const summary = await atmosphere.syncSoundsFolder()
      if (summary) {
        setMessage(
          summary.description +
            (summary.notDownloaded > 0
              ? ". Files still in iCloud are downloading; check again in a while."
              : "."),
        )
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setSyncing(false)
    }
  }

  async function showSoundCredits() {
    try {
      const text = await LofiScore?.getAtmosphereCredits()
      setCredits(
        text
          ? plainCredits(text)
          : "The Atmosphere folder came without a CREDITS.md file.",
      )
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error))
    }
  }

  return (
    <View className="mt-8 w-full gap-4">
      <Text variant="h2">Atmosphere Sounds</Text>
      <Text variant="p" className="text-sm">
        The quiet sounds of each scene under the narration of readaloud books:
        rain on the windows, a fire, the sea, a crowded hall. Each book is
        scored ahead of time, and the sounds only ever follow what you have
        already heard, so they never give away what comes next. Turn them on or
        off and change their volume from the sounds button in the player too.
      </Text>
      <LofiAtmosphereControls atmosphere={atmosphere} />
      {status && (
        <View className="w-full flex-row items-center justify-between gap-4">
          <View className="shrink gap-1">
            <Text maxFontSizeMultiplier={1.5}>Sounds while reading</Text>
            <Text variant="muted">
              With the narration stopped, the sounds follow the pages as you
              read a readaloud book on screen, placed at the top of the page.
            </Text>
          </View>
          <Switch
            accessibilityLabel="Sounds while reading"
            checked={status.followsReading}
            disabled={!status.atmosphere.enabled}
            onCheckedChange={(enabled) =>
              void atmosphere.setFollowsReading(enabled)
            }
          />
        </View>
      )}
      {status?.atmosphere.pausesAvailable && (
        <View className="w-full flex-row items-center justify-between gap-4">
          <View className="shrink gap-1">
            <Text maxFontSizeMultiplier={1.5}>
              Short pauses for big scene changes
            </Text>
            <Text variant="muted">
              The narrator stops for under a second while the sound swells, like
              walking into a crowded hall or a storm breaking, or goes quiet,
              then carries on.
            </Text>
          </View>
          <Switch
            accessibilityLabel="Short pauses for big scene changes"
            checked={status.atmosphere.pausesEnabled}
            disabled={!status.atmosphere.enabled}
            onCheckedChange={(enabled) => void atmosphere.setPauses(enabled)}
          />
        </View>
      )}
      {status && (
        <View className="w-full flex-row items-center justify-between gap-4">
          <View className="shrink gap-1">
            <Text maxFontSizeMultiplier={1.5}>One-off sounds</Text>
            <Text variant="muted">
              A single sound on the sentence that says it happens, like a knock
              at the door or a clap of thunder. Rare and quiet, and off unless
              you turn it on.
            </Text>
          </View>
          <Switch
            accessibilityLabel="One-off sounds"
            checked={status.atmosphere.oneShotsEnabled}
            disabled={!status.atmosphere.enabled}
            onCheckedChange={(enabled) => void atmosphere.setOneShots(enabled)}
          />
        </View>
      )}
      {status && (
        <View className="w-full gap-2">
          <Text maxFontSizeMultiplier={1.5} className="mt-2 text-lg">
            Sounds folder
          </Text>
          <Text variant="muted">
            {atmosphereSourceLabel(status.atmosphere)}
          </Text>
          <Text variant="muted">
            The sounds come from an Atmosphere folder inside the folder you
            pick, with one subfolder per sound (Rain, Fireplace, Crowd, …), and
            play for books with an atmosphere track.
            {status.atmosphere.edition === "personal" &&
              " This build may also play recordings that are for personal use only; a published build leaves them out."}
          </Text>
          <Button
            accessibilityLabel={
              status.folder.linkedFolder
                ? "Pick a different sounds folder"
                : "Import a sounds folder"
            }
            variant="secondary"
            disabled={importing || syncing}
            onPress={() => void importFolder()}
          >
            <Icon as={FolderInput} />
            <Text>
              {importing
                ? "Importing…"
                : status.folder.linkedFolder
                  ? "Pick a different sounds folder"
                  : "Import a sounds folder"}
            </Text>
          </Button>
          {status.folder.linkedFolder ? (
            <>
              <Text variant="muted">
                {linkedFolderLabel(status.folder.linkedFolder)} New book scores,
                sounds and tracks put into the folder are copied by themselves
                when the app opens, comes back, or opens a book that has no
                score yet.
              </Text>
              <Button
                accessibilityLabel="Check the sounds folder for new files now"
                variant="secondary"
                disabled={importing || syncing}
                onPress={() => void syncFolder()}
              >
                <Icon as={FolderSync} />
                <Text>{syncing ? "Checking…" : "Check for new files now"}</Text>
              </Button>
            </>
          ) : (
            <Text variant="muted">
              Pick the folder the Mac scores into, for example from iCloud
              Drive. The sounds and scores are copied into the app, and the
              folder is kept linked so new scores, sounds and tracks arrive by
              themselves.
            </Text>
          )}
          {(status.atmosphere.source === "imported" ||
            status.atmosphere.source === "mixed") && (
            <Button
              accessibilityLabel="Show the sound credits"
              variant="ghost"
              onPress={() => void showSoundCredits()}
            >
              <Text>Sound credits</Text>
            </Button>
          )}
          {status.folder.linkedFolder && (
            <Button
              accessibilityLabel="Stop keeping the sounds folder up to date"
              variant="ghost"
              disabled={importing || syncing}
              onPress={() => void atmosphere.unlinkSoundsFolder()}
            >
              <Text>Stop keeping it up to date</Text>
            </Button>
          )}
          {status.folder.imported && (
            <Button
              accessibilityLabel="Remove the imported sounds"
              variant="ghost"
              disabled={importing || syncing}
              onPress={() => void atmosphere.removeImportedSounds()}
            >
              <Text>Remove imported sounds</Text>
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
            accessibilityLabel="Close the credits"
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
