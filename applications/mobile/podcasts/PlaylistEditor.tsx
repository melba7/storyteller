// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { randomUUID } from "expo-crypto"
import { Stack, useRouter, useSegments } from "expo-router"
import { useEffect, useState } from "react"
import { ActivityIndicator, Alert, ScrollView } from "react-native"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Text } from "@/components/ui/text"
import {
  deletePlaylist,
  nextPlaylistPosition,
  savePlaylist,
} from "@/modules/podcasts/dbPlaylists"
import { readableError } from "@/modules/podcasts/nativeError"
import {
  DOWNLOADED_CHOICES,
  PLAYED_CHOICES,
  type PlayedState,
  type PlaylistRules,
  RELEASE_CHOICES,
  SORT_CHOICES,
} from "@/modules/podcasts/playlistRules"
import {
  type Playlist,
  newPlaylist,
  parseMinutes,
  playlistProblem,
} from "@/modules/podcasts/playlists"
import { tabBase } from "@/modules/podcasts/routes"

import {
  ChoiceRow,
  Heading,
  PickRows,
  Row,
  SwitchRow,
  showOptions,
} from "./PlaylistFields"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { useShows } from "./hooks"
import { usePlaylist } from "./usePlaylists"

function toggled<T>(list: readonly T[], item: T): T[] {
  return list.includes(item)
    ? list.filter((other) => other !== item)
    : [...list, item]
}

/**
 * Makes a smart playlist (`id` "new") or changes one: its name, the rules, the order and
 * whether its first episodes download by themselves. Deleting asks first.
 */
export function PlaylistEditor({ id }: { id: string }) {
  const router = useRouter()
  const segments = useSegments()
  const creating = id === "new"
  const existing = usePlaylist(creating ? "" : id)
  const shows = useShows()
  const [draft, setDraft] = useState<Playlist | null>(null)
  const [shorter, setShorter] = useState("")
  const [longer, setLonger] = useState("")
  const [problem, setProblem] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (draft) return
    if (creating) {
      nextPlaylistPosition().then(
        (position) => setDraft(newPlaylist(randomUUID(), position, Date.now())),
        (cause: unknown) => setProblem(readableError(cause)),
      )
    } else if (existing.data) {
      setDraft(existing.data)
      const { shorterThan, longerThan } = existing.data.rules
      setShorter(shorterThan === null ? "" : String(shorterThan))
      setLonger(longerThan === null ? "" : String(longerThan))
    }
  }, [creating, existing.data, draft])

  if (!draft) {
    return (
      <>
        {existing.loading && !creating ? (
          <BelowBar>
            <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
          </BelowBar>
        ) : (
          <BelowBar>
            <Text className="text-muted-foreground px-8 py-12 text-center">
              {problem ?? existing.error ?? "This playlist isn't there."}
            </Text>
          </BelowBar>
        )}
        <ScreenBar title={creating ? "New playlist" : "Playlist"} />
      </>
    )
  }

  const rules = draft.rules
  const change = (patch: Partial<PlaylistRules>) =>
    setDraft({ ...draft, rules: { ...rules, ...patch } })
  // The length boxes are text; they become the rules' numbers when saving.
  const finished: Playlist = {
    ...draft,
    title: draft.title.trim(),
    rules: {
      ...rules,
      shorterThan: parseMinutes(shorter),
      longerThan: parseMinutes(longer),
    },
  }

  async function save() {
    const trouble = playlistProblem(
      finished.title,
      finished.rules,
      finished.autoDownload,
    )
    if (trouble) return setProblem(trouble)
    setSaving(true)
    try {
      await savePlaylist(finished)
      router.back()
    } catch (cause) {
      setProblem(readableError(cause))
      setSaving(false)
    }
  }

  function confirmDelete() {
    Alert.alert(
      `Delete ${finished.title || "this playlist"}?`,
      "Only the playlist goes. Your episodes stay.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Delete",
          style: "destructive",
          onPress: () => {
            deletePlaylist(draft?.id ?? "").then(
              // Back past the playlist's own page, which is gone now.
              () => router.dismissTo(tabBase(segments)),
              (cause: unknown) => setProblem(readableError(cause)),
            )
          },
        },
      ],
    )
  }

  return (
    <>
      <ScrollView
        className="bg-background flex-1"
        contentInsetAdjustmentBehavior="automatic"
        contentContainerClassName="px-safe-or-4 pb-12"
        keyboardShouldPersistTaps="handled"
      >
        {problem ? (
          <Text className="text-destructive py-2" accessibilityRole="alert">
            {problem}
          </Text>
        ) : null}
        <Heading>Name</Heading>
        <Input
          value={draft.title}
          onChangeText={(title) => setDraft({ ...draft, title })}
          placeholder="Playlist name"
          accessibilityLabel="Playlist name"
          returnKeyType="done"
        />

        <Heading>Shows</Heading>
        <SwitchRow
          title="All shows"
          checked={rules.showIds === null}
          onChange={(on) => change({ showIds: on ? null : [] })}
        />
        {rules.showIds === null ? null : (
          <PickRows
            options={showOptions(shows.data ?? [])}
            picked={rules.showIds}
            onToggle={(show) =>
              change({ showIds: toggled(rules.showIds ?? [], show) })
            }
          />
        )}

        <Heading>Episodes</Heading>
        <Text className="text-muted-foreground pb-1 text-sm">
          Played state (none ticked takes every episode)
        </Text>
        <PickRows
          options={PLAYED_CHOICES}
          picked={rules.played}
          onToggle={(state) =>
            change({ played: toggled(rules.played, state as PlayedState) })
          }
        />
        <ChoiceRow
          title="Released"
          value={rules.release}
          choices={RELEASE_CHOICES}
          onChange={(release) => change({ release })}
        />
        <Row title="Shorter than (minutes)">
          <Input
            className="w-24"
            value={shorter}
            onChangeText={setShorter}
            keyboardType="number-pad"
            placeholder="Any"
            accessibilityLabel="Shorter than, in minutes"
          />
        </Row>
        <Row title="Longer than (minutes)">
          <Input
            className="w-24"
            value={longer}
            onChangeText={setLonger}
            keyboardType="number-pad"
            placeholder="Any"
            accessibilityLabel="Longer than, in minutes"
          />
        </Row>
        <ChoiceRow
          title="On the phone"
          value={rules.downloaded}
          choices={DOWNLOADED_CHOICES}
          onChange={(downloaded) => change({ downloaded })}
        />
        <SwitchRow
          title="Starred only"
          checked={rules.starredOnly}
          onChange={(starredOnly) => change({ starredOnly })}
        />

        <Heading>Order and downloads</Heading>
        <ChoiceRow
          title="Order"
          value={draft.sort}
          choices={SORT_CHOICES}
          onChange={(sort) => setDraft({ ...draft, sort })}
        />
        <SwitchRow
          title="Download the first episodes"
          body="Keeps the first 5 episodes of this playlist downloaded, on Wi-Fi only."
          checked={draft.autoDownload}
          onChange={(autoDownload) => setDraft({ ...draft, autoDownload })}
        />

        {creating ? null : (
          <Button
            variant="ghost"
            className="mt-6"
            accessibilityLabel="Delete the playlist"
            onPress={confirmDelete}
          >
            <Text className="text-destructive">Delete playlist</Text>
          </Button>
        )}
      </ScrollView>
      <ScreenBar
        title={creating ? "New playlist" : "Edit playlist"}
        right={
          <Stack.Toolbar.Button
            variant="done"
            disabled={saving}
            accessibilityLabel="Save the playlist"
            onPress={save}
          >
            Save
          </Stack.Toolbar.Button>
        }
      />
    </>
  )
}
