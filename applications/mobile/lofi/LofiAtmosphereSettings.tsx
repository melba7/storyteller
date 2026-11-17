// LOFI-FORK: the atmosphere's section in Settings (see FORK.md).
import { FolderInput, FolderSync } from "lucide-react-native"
import { useState } from "react"
import { Modal, ScrollView, View } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { GroupedRow, GroupedSection } from "@/apple-look/GroupedList"
import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import { LofiScore } from "@/modules/lofi-score"
import {
  atmosphereSourceLabel,
  copyingLabel,
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
  // The copy runs in the app, not in this screen: coming back to the screen while it
  // is still going shows its count again.
  const copying = status?.folder.linkedFolder
    ? copyingLabel(status.folder.linkedFolder)
    : null
  const busy = importing || syncing || !!status?.folder.linkedFolder?.syncing

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
            `${summary.notDownloaded} files were still in iCloud and are downloading: tap “Check for new files now” in a while to copy them.`,
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

  const mutedNote = "text-muted-foreground text-[13px]"

  return (
    <View className="w-full">
      <LofiAtmosphereControls
        atmosphere={atmosphere}
        title="Atmosphere sounds"
        footer="The quiet sounds of each scene under the narration of readaloud books: rain on the windows, a fire, the sea, a crowded hall. Each book is scored ahead of time, and the sounds only ever follow what you have already heard, so they never give away what comes next. Turn them on or off and change their volume from the sounds button in the player too."
      />
      {status && (
        <GroupedSection>
          <GroupedRow
            title="Sounds while reading"
            subtitle="With the narration stopped, the sounds follow the pages as you read a readaloud book on screen, placed at the top of the page."
            trailing={
              <Switch
                accessibilityLabel="Sounds while reading"
                checked={status.followsReading}
                disabled={!status.atmosphere.enabled}
                onCheckedChange={(enabled) =>
                  void atmosphere.setFollowsReading(enabled)
                }
              />
            }
          />
          {status.atmosphere.pausesAvailable ? (
            <GroupedRow
              title="Short pauses for big scene changes"
              subtitle="The narrator stops for under a second while the sound swells, like walking into a crowded hall or a storm breaking, or goes quiet, then carries on."
              trailing={
                <Switch
                  accessibilityLabel="Short pauses for big scene changes"
                  checked={status.atmosphere.pausesEnabled}
                  disabled={!status.atmosphere.enabled}
                  onCheckedChange={(enabled) =>
                    void atmosphere.setPauses(enabled)
                  }
                />
              }
            />
          ) : null}
          <GroupedRow
            title="One-off sounds"
            subtitle="A single sound on the sentence that says it happens, like a knock at the door or a clap of thunder, and the door or the engine when the story moves on. Rare and quiet; turn it off if sudden sounds are not for you."
            trailing={
              <Switch
                accessibilityLabel="One-off sounds"
                checked={status.atmosphere.oneShotsEnabled}
                disabled={!status.atmosphere.enabled}
                onCheckedChange={(enabled) =>
                  void atmosphere.setOneShots(enabled)
                }
              />
            }
          />
        </GroupedSection>
      )}
      {status && (
        <GroupedSection
          title="Sounds folder"
          footer={
            <View className="gap-2">
              <Text className={mutedNote}>
                The sounds come from an Atmosphere folder inside the folder you
                pick, with one subfolder per sound (Rain, Fireplace, Crowd, …),
                and play for books with an atmosphere track.
                {status.atmosphere.edition === "personal" &&
                  " This build may also play recordings that are for personal use only; a published build leaves them out."}
              </Text>
              {status.folder.linkedFolder ? (
                <Text className={mutedNote}>
                  {linkedFolderLabel(status.folder.linkedFolder)} New book
                  scores, sounds and tracks put into the folder are copied by
                  themselves when the app opens, comes back, or opens a book
                  that has no score yet.
                </Text>
              ) : (
                <Text className={mutedNote}>
                  Pick the folder the Mac scores into, for example from iCloud
                  Drive. The sounds and scores are copied into the app, and the
                  folder is kept linked so new scores, sounds and tracks arrive
                  by themselves.
                </Text>
              )}
              {message && <Text className={mutedNote}>{message}</Text>}
              {status.lastError && (
                <Text className={mutedNote}>
                  Last problem: {status.lastError}
                </Text>
              )}
            </View>
          }
        >
          <GroupedRow subtitle={atmosphereSourceLabel(status.atmosphere)} />
          <GroupedRow className="py-2">
            <Button
              accessibilityLabel={
                status.folder.linkedFolder
                  ? "Pick a different sounds folder"
                  : "Import a sounds folder"
              }
              variant="secondary"
              disabled={busy}
              onPress={() => void importFolder()}
            >
              <Icon as={FolderInput} />
              <Text>
                {importing
                  ? (copying ?? "Importing…")
                  : status.folder.linkedFolder
                    ? "Pick a different sounds folder"
                    : "Import a sounds folder"}
              </Text>
            </Button>
          </GroupedRow>
          {status.folder.linkedFolder ? (
            <GroupedRow className="py-2">
              <Button
                accessibilityLabel="Check the sounds folder for new files now"
                variant="secondary"
                disabled={busy}
                onPress={() => void syncFolder()}
              >
                <Icon as={FolderSync} />
                <Text>
                  {syncing || (!importing && copying)
                    ? (copying ?? "Checking…")
                    : "Check for new files now"}
                </Text>
              </Button>
            </GroupedRow>
          ) : null}
          {status.atmosphere.source === "imported" ||
          status.atmosphere.source === "mixed" ? (
            <GroupedRow className="py-1">
              <Button
                accessibilityLabel="Show the sound credits"
                variant="ghost"
                onPress={() => void showSoundCredits()}
              >
                <Text>Sound credits</Text>
              </Button>
            </GroupedRow>
          ) : null}
          {status.folder.linkedFolder ? (
            <GroupedRow className="py-1">
              <Button
                accessibilityLabel="Stop keeping the sounds folder up to date"
                variant="ghost"
                disabled={busy}
                onPress={() => void atmosphere.unlinkSoundsFolder()}
              >
                <Text>Stop keeping it up to date</Text>
              </Button>
            </GroupedRow>
          ) : null}
          {status.folder.imported ? (
            <GroupedRow className="py-1">
              <Button
                accessibilityLabel="Remove the imported sounds"
                variant="ghost"
                disabled={busy}
                onPress={() => void atmosphere.removeImportedSounds()}
              >
                <Text>Remove imported sounds</Text>
              </Button>
            </GroupedRow>
          ) : null}
        </GroupedSection>
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
          className="bg-secondary dark:bg-background flex-1 px-6 pt-6"
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
