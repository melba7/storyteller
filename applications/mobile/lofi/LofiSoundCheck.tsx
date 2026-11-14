// LOFI-FORK: the sound check in the atmosphere panel: plays a few spots of the
// book already heard and asks how each one sounded (see FORK.md).
import { useEffect, useRef, useState } from "react"
import { Share, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { logger } from "@/logger"
import { LofiScore } from "@/modules/lofi-score"
import {
  answerStop,
  currentStop,
  rememberedResults,
  rememberResults,
  resultsText,
  SOUND_CHECK_ANSWERS,
  SOUND_CHECK_LISTEN_MS,
  type SoundCheckAnswer,
  type SoundCheckSession,
  startSoundCheck,
  stopLabel,
} from "@/modules/lofi-score/soundCheck"
import { Storyteller } from "@/modules/readium"

import { type LofiAtmosphere } from "./useLofiAtmosphere"

type Props = {
  atmosphere: LofiAtmosphere
}

type Phase =
  | { name: "idle"; message?: string }
  | { name: "loading" }
  | { name: "listening"; until: number }
  | { name: "asking" }
  | { name: "done" }

/** Where the narration was before the check, to put it back afterwards. */
type Resume = { relativeUri: string; position: number; wasPlaying: boolean }

export function LofiSoundCheck({ atmosphere }: Props) {
  const [phase, setPhase] = useState<Phase>({ name: "idle" })
  const [session, setSession] = useState<SoundCheckSession | null>(null)
  const [now, setNow] = useState(Date.now())
  const resume = useRef<Resume | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const clearTimer = () => {
    if (timer.current) clearTimeout(timer.current)
    timer.current = null
  }

  // A countdown while a stop plays.
  useEffect(() => {
    if (phase.name !== "listening") return
    const tick = setInterval(() => setNow(Date.now()), 500)
    return () => clearInterval(tick)
  }, [phase.name])

  // Closing the panel mid-check puts the narration back.
  useEffect(
    () => () => {
      clearTimer()
      void putNarrationBack()
    },
    [],
  )

  async function putNarrationBack() {
    const saved = resume.current
    resume.current = null
    if (!saved) return
    try {
      await Storyteller.pause()
      await Storyteller.seekTo(saved.relativeUri, saved.position)
      if (saved.wasPlaying) await Storyteller.play(false)
    } catch (error) {
      logger.error(`Lofi sound check, going back: ${String(error)}`)
    }
  }

  async function playStop(next: SoundCheckSession) {
    const stop = currentStop(next)
    if (!stop) {
      await putNarrationBack()
      rememberResults(results(next))
      setPhase({ name: "done" })
      return
    }
    try {
      await Storyteller.seekTo(stop.relativeUrl, stop.start)
      await Storyteller.play(false)
    } catch (error) {
      logger.error(`Lofi sound check, playing a stop: ${String(error)}`)
    }
    const until = Date.now() + SOUND_CHECK_LISTEN_MS
    setNow(Date.now())
    setPhase({ name: "listening", until })
    clearTimer()
    timer.current = setTimeout(() => {
      void Storyteller.pause()
      setPhase({ name: "asking" })
    }, SOUND_CHECK_LISTEN_MS)
  }

  async function start() {
    if (!LofiScore) return
    setPhase({ name: "loading" })
    try {
      const stops = await LofiScore.getSoundCheckStops(6)
      if (stops.length === 0) {
        setPhase({
          name: "idle",
          message:
            "No spots to check yet. Listen a little further into the book first.",
        })
        return
      }
      const [track, position, wasPlaying] = await Promise.all([
        Storyteller.getCurrentTrack(),
        Storyteller.getPosition(),
        atmosphere.status?.playback.narrating ?? false,
      ])
      resume.current = track
        ? { relativeUri: track.relativeUri, position, wasPlaying }
        : null
      const fresh = startSoundCheck(stops)
      setSession(fresh)
      await playStop(fresh)
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      setPhase({ name: "idle", message })
    }
  }

  function answer(value: SoundCheckAnswer) {
    if (!session) return
    const next = answerStop(session, value)
    setSession(next)
    void playStop(next)
  }

  function results(of: SoundCheckSession) {
    const sounds = atmosphere.status?.atmosphere
    return resultsText(of, {
      book: atmosphere.status?.book?.id ?? "unknown book",
      levelDB: sounds?.levelDB ?? 0,
      defaultLevelDB: sounds?.defaultLevelDB ?? 0,
      intensity: sounds?.intensity ?? 0,
    })
  }

  async function stop() {
    clearTimer()
    await putNarrationBack()
    if (session && session.answers.length > 0) {
      rememberResults(results(session))
      setPhase({ name: "done" })
    } else {
      setPhase({ name: "idle" })
    }
  }

  const lastResults = rememberedResults()
  const stopNow = session ? currentStop(session) : null
  const position = session
    ? `${Math.min(session.answers.length + 1, session.stops.length)} of ${session.stops.length}`
    : ""

  if (phase.name === "listening" || phase.name === "asking") {
    const seconds = Math.max(
      0,
      Math.ceil((phase.name === "listening" ? phase.until - now : 0) / 1000),
    )
    return (
      <View className="w-full gap-3">
        <Text maxFontSizeMultiplier={1.5} className="text-lg">
          Sound check, {position}
        </Text>
        {stopNow && (
          <Text variant="muted">Listen for: {stopLabel(stopNow)}</Text>
        )}
        {phase.name === "listening" ? (
          <Text>Listening… {seconds} s</Text>
        ) : (
          <View className="w-full gap-2">
            <Text>How did the sounds come through?</Text>
            <View className="w-full flex-row flex-wrap gap-2">
              {SOUND_CHECK_ANSWERS.map(({ value, label }) => (
                <Button
                  key={value}
                  accessibilityLabel={label}
                  variant="secondary"
                  size="sm"
                  onPress={() => answer(value)}
                >
                  <Text>{label}</Text>
                </Button>
              ))}
            </View>
          </View>
        )}
        <Button variant="ghost" size="sm" onPress={() => void stop()}>
          <Text>Stop the sound check</Text>
        </Button>
      </View>
    )
  }

  const message = phase.name === "idle" ? phase.message : undefined
  return (
    <View className="w-full gap-2">
      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5}>Sound check</Text>
          <Text variant="muted">
            About 3 minutes: a few spots you have already heard, then a question
            for each.
          </Text>
        </View>
        <Button
          accessibilityLabel="Start the sound check"
          variant="secondary"
          size="sm"
          disabled={
            phase.name === "loading" || !atmosphere.status?.atmosphere.enabled
          }
          onPress={() => void start()}
        >
          <Text>{phase.name === "loading" ? "Starting…" : "Start"}</Text>
        </Button>
      </View>
      {message && <Text variant="muted">{message}</Text>}
      {phase.name === "done" && (
        <Text>Thanks, that&apos;s the sound check done.</Text>
      )}
      {lastResults && (
        <Button
          accessibilityLabel="Share the sound check results"
          variant="ghost"
          size="sm"
          onPress={() => {
            if (lastResults) void Share.share({ message: lastResults })
          }}
        >
          <Text>Share results</Text>
        </Button>
      )}
    </View>
  )
}
