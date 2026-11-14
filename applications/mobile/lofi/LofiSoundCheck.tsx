// LOFI-FORK: the sound check in the atmosphere panel: plays a few spots of the
// book already heard and asks how each one sounded (see FORK.md).
import AsyncStorage from "@react-native-async-storage/async-storage"
import { skipToken } from "@reduxjs/toolkit/query"
import Constants from "expo-constants"
import { useEffect, useRef, useState } from "react"
import { AppState, Share, View } from "react-native"

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
      wait: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
      now: () => Date.now(),
    },
    onChange,
  )
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

  // A check the app closed in the middle of: put the narration back, and
  // show the last results kept on the phone.
  useEffect(() => {
    if (bookUuid) {
      runner.current?.restoreLeftover(bookUuid).catch((error: unknown) => {
        logger.error(`Lofi sound check, restoring: ${String(error)}`)
      })
    }
    void keptResults(AsyncStorage).then((runs) =>
      setLastResults(runs[0] ?? null),
    )
  }, [bookUuid])

  // Closing the panel or leaving the app stops the check and puts the
  // narration back.
  useEffect(() => {
    const current = runner.current
    const subscription = AppState.addEventListener("change", (next) => {
      if (next === "background") void current?.stop()
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
      appVersion: Constants.expoConfig?.version ?? "unknown",
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
      <View className="w-full gap-3">
        <Text maxFontSizeMultiplier={1.5} className="text-lg">
          Sound check, {state.index + 1} of {state.stops.length}
        </Text>
        {stop && <Text variant="muted">{stopLabel(stop)}</Text>}
        {phase === "jumping" && <Text>Finding the spot…</Text>}
        {phase === "listening" && <Text>Listening… {state.secondsLeft} s</Text>}
        {phase === "asking" && stop && (
          <View className="w-full gap-2">
            <Text>{stopQuestion(stop)}</Text>
            {SOUND_CHECK_ANSWERS.map(({ value, label, hint }) => (
              <Button
                key={value}
                accessibilityLabel={`${label}: ${hint}`}
                variant="secondary"
                size="sm"
                className="w-full justify-start"
                onPress={() => void check.answer(value)}
              >
                <Text>
                  {label}: {hint}
                </Text>
              </Button>
            ))}
            <Button
              variant="ghost"
              size="sm"
              onPress={() => void check.playAgain()}
            >
              <Text>Play it again</Text>
            </Button>
          </View>
        )}
        <Button variant="ghost" size="sm" onPress={() => void check.stop()}>
          <Text>Stop the sound check</Text>
        </Button>
      </View>
    )
  }

  const reason = cannotStartReason(atmosphere.status)
  const standIns =
    atmosphere.status?.atmosphere.source === "standIns" ||
    atmosphere.status?.atmosphere.source === "mixed"
  const message = state?.message ?? reason
  return (
    <View className="w-full gap-2">
      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5}>Sound check</Text>
          <Text variant="muted">
            About 3 minutes: a few spots you have already heard, then a question
            for each. Your place is kept.
          </Text>
        </View>
        <Button
          accessibilityLabel="Start the sound check"
          variant="secondary"
          size="sm"
          disabled={phase === "starting" || reason !== null || !bookUuid}
          onPress={() => {
            if (bookUuid) void check.start(bookUuid)
          }}
        >
          <Text>{phase === "starting" ? "Starting…" : "Start"}</Text>
        </Button>
      </View>
      {message && <Text variant="muted">{message}</Text>}
      {standIns && !reason && (
        <Text variant="muted">
          Some sounds are stand-ins, not recordings, so they may sound off.
        </Text>
      )}
      {phase === "done" && (
        <Text>Thanks, that&apos;s the sound check done.</Text>
      )}
      {lastResults && (
        <Button
          accessibilityLabel="Share the sound check results"
          variant="ghost"
          size="sm"
          onPress={() => void Share.share({ message: lastResults })}
        >
          <Text>Share results</Text>
        </Button>
      )}
    </View>
  )
}
