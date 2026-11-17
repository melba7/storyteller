// LOFI-FORK: the sound check in the atmosphere panel: plays a few spots of the
// book already heard (or its opening) and asks how each one sounded (see
// FORK.md).
import AsyncStorage from "@react-native-async-storage/async-storage"
import { skipToken } from "@reduxjs/toolkit/query"
import Constants from "expo-constants"
import { useKeepAwake } from "expo-keep-awake"
import { useEffect, useRef, useState } from "react"
import { AppState, Share, View } from "react-native"

import { GroupedRow, GroupedSection } from "@/apple-look/GroupedList"
import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { logger } from "@/logger"
import { LofiScore } from "@/modules/lofi-score"
import {
  resultsText,
  SOUND_CHECK_ANSWERS,
  stopLabel,
  stopQuestion,
} from "@/modules/lofi-score/soundCheck"
import {
  cannotStartReason,
  keepResults,
  keptResults,
  restoreLeftoverPlace,
  SoundCheckRunner,
  type SoundCheckState,
} from "@/modules/lofi-score/soundCheckRunner"
import { Storyteller } from "@/modules/readium"
import { useAppSelector } from "@/store/appState"
import { useGetBookQuery } from "@/store/localApi"
import {
  getCurrentlyPlayingBookUuid,
  getPlaybackRate,
} from "@/store/selectors/bookshelfSelectors"

import { type LofiAtmosphere } from "./useLofiAtmosphere"

type Props = {
  atmosphere: LofiAtmosphere
}

function makeRunner(onChange: (state: SoundCheckState) => void) {
  const native = LofiScore
  if (!native) return null
  return new SoundCheckRunner(
    {
      player: Storyteller,
      storage: AsyncStorage,
      getStatus: () => native.getStatus(),
      getStops: (count) => native.getSoundCheckStops(count),
      getReading: () => native.getSoundCheckReading(),
      willJump: (globalIndex) => native.soundCheckWillJump(globalIndex),
      wait: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
      now: () => Date.now(),
    },
    onChange,
  )
}

/** The screen stays on while a check runs: a lock in the middle would end it. */
function KeepAwake() {
  useKeepAwake("lofi-sound-check")
  return null
}

/** The app's version, with the build number when the build has one. */
function appVersion() {
  const version = Constants.expoConfig?.version ?? "unknown"
  const build = Constants.expoConfig?.ios?.buildNumber
  return build ? `${version} (${build})` : version
}

export function LofiSoundCheck({ atmosphere }: Props) {
  const [state, setState] = useState<SoundCheckState | null>(null)
  const [lastResults, setLastResults] = useState<string | null>(null)
  const runner = useRef<SoundCheckRunner | null>(null)
  if (runner.current === null) runner.current = makeRunner(setState)

  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)
  const playbackRate = useAppSelector(getPlaybackRate)
  const { data: book } = useGetBookQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )

  // A check the app closed in the middle of: put the narration back (the
  // toolbar tries first, when the book opens; this is the second try), and
  // show the last results kept on the phone.
  useEffect(() => {
    if (bookUuid) {
      restoreLeftoverPlace(Storyteller, AsyncStorage, bookUuid).catch(
        (error: unknown) => {
          logger.error(`Lofi sound check, restoring: ${String(error)}`)
        },
      )
    }
    void keptResults(AsyncStorage).then((runs) =>
      setLastResults(runs[0] ?? null),
    )
  }, [bookUuid])

  // Closing the panel or leaving the app stops the check and puts the
  // narration back. In the background it stays paused there: the phone may
  // have locked with nobody listening.
  useEffect(() => {
    const current = runner.current
    const subscription = AppState.addEventListener("change", (next) => {
      if (next === "background") void current?.stop(false)
    })
    return () => {
      subscription.remove()
      void current?.stop()
    }
  }, [])

  // A finished run's results are written once and kept.
  const phase = state?.phase ?? "idle"
  const finished = state && phase === "done" ? state : null
  const written = useRef<SoundCheckState | null>(null)
  const sounds = atmosphere.status?.atmosphere
  const title = book?.title ?? bookUuid ?? "unknown book"
  useEffect(() => {
    if (!finished || written.current === finished) return
    written.current = finished
    const text = resultsText(finished.stops, finished.results, {
      book: title,
      appVersion: appVersion(),
      edition: sounds?.edition ?? "unknown",
      levelDB: sounds?.levelDB ?? 0,
      defaultLevelDB: sounds?.defaultLevelDB ?? 0,
      intensity: sounds?.intensity ?? 0,
      defaultIntensity: sounds?.defaultIntensity ?? 0,
      source: sounds?.source ?? "unknown",
      playbackRate,
      startedAt: new Date().toISOString().slice(0, 16).replace("T", " "),
    })
    setLastResults(text)
    void keepResults(AsyncStorage, text)
  }, [finished, sounds, title, playbackRate])

  if (!runner.current) return null
  const check = runner.current

  if (state && ["jumping", "listening", "asking"].includes(phase)) {
    const stop = state.stops[state.index]
    return (
      <>
        <KeepAwake />
        <GroupedSection
          title={`Sound check, ${state.index + 1} of ${state.stops.length}`}
        >
          <GroupedRow
            title={
              phase === "jumping"
                ? "Finding the spot…"
                : phase === "listening"
                  ? stop?.cueIndex === undefined
                    ? `Listening… ${state.secondsLeft} s`
                    : "Listening… the sound comes after a few seconds"
                  : stop
                    ? stopQuestion(stop)
                    : undefined
            }
            subtitle={stop ? stopLabel(stop) : undefined}
          />
          {phase === "asking" && stop
            ? SOUND_CHECK_ANSWERS.map(({ value, label, hint }) => (
                <GroupedRow
                  key={value}
                  accessibilityLabel={`${label}: ${hint}`}
                  title={label}
                  subtitle={hint}
                  hideChevron
                  onPress={() => void check.answer(value)}
                />
              ))
            : null}
          {phase === "asking" && stop ? (
            <GroupedRow className="py-1">
              <Button
                variant="ghost"
                size="sm"
                onPress={() => void check.playAgain()}
              >
                <Text>Play it again</Text>
              </Button>
            </GroupedRow>
          ) : null}
          <GroupedRow className="py-1">
            <Button variant="ghost" size="sm" onPress={() => void check.stop()}>
              <Text>Stop the sound check</Text>
            </Button>
          </GroupedRow>
        </GroupedSection>
      </>
    )
  }

  const reason = cannotStartReason(atmosphere.status)
  const standIns =
    atmosphere.status?.atmosphere.source === "standIns" ||
    atmosphere.status?.atmosphere.source === "mixed"
  const message = state?.message ?? reason
  const notes = [
    phase === "restoring" ? "Putting your place back…" : null,
    message,
    standIns && !reason
      ? "Some sounds are stand-ins, not recordings, so they may sound off."
      : null,
  ].filter((note): note is string => !!note)
  return (
    <GroupedSection
      footer={
        notes.length > 0 ? (
          <View className="gap-1">
            {notes.map((note) => (
              <Text key={note} className="text-muted-foreground text-[13px]">
                {note}
              </Text>
            ))}
          </View>
        ) : undefined
      }
    >
      <GroupedRow
        title="Sound check"
        subtitle="About 3 minutes: a few spots you have already heard, or from the book's opening if you are not far in, then a question for each. Your place is kept."
        trailing={
          <Button
            accessibilityLabel="Start the sound check"
            variant="secondary"
            size="sm"
            disabled={
              phase === "starting" ||
              phase === "restoring" ||
              reason !== null ||
              !bookUuid
            }
            onPress={() => {
              if (bookUuid) void check.start(bookUuid)
            }}
          >
            <Text>{phase === "starting" ? "Starting…" : "Start"}</Text>
          </Button>
        }
      />
      {phase === "done" ? (
        <GroupedRow title="Thanks, that's the sound check done." />
      ) : null}
      {lastResults ? (
        <GroupedRow className="py-1">
          <Button
            accessibilityLabel="Share the sound check results"
            variant="ghost"
            size="sm"
            onPress={() => void Share.share({ message: lastResults })}
          >
            <Text>Share results</Text>
          </Button>
        </GroupedRow>
      ) : null}
    </GroupedSection>
  )
}
