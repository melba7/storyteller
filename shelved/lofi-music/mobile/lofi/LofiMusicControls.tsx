// LOFI-FORK: the lofi music's controls, shared by the player's music panel and
// Settings (see FORK.md).
import { useState } from "react"
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import {
  canMarkWrongMood,
  describeAtmosphere,
  describeMusic,
  intensityLabel,
  moodFeedbackLine,
  moodName,
  musicLevelLabel,
  nowPlayingLine,
  wrongMoodResult,
} from "@/modules/lofi-score/status"

import { type LofiMusic } from "./useLofiMusic"

type Props = {
  music: LofiMusic
}

export function LofiMusicControls({ music }: Props) {
  const { status } = music
  if (!status) {
    return (
      <Text variant="muted" className="py-4">
        Loading the music…
      </Text>
    )
  }

  const [quietest = -30, loudest = -4] = status.musicLevelRange
  const level = Math.min(loudest, Math.max(quietest, status.musicLevelDB))
  const isDefaultLevel =
    Math.round(level) === Math.round(status.defaultMusicLevelDB)
  const atmosphere = status.atmosphere?.available ? status.atmosphere : null

  return (
    <View className="w-full gap-5">
      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5} className="text-lg">
            Lofi music
          </Text>
          <Text variant="muted">{describeMusic(status)}</Text>
          {status.enabled && status.playback.nowPlaying && (
            <Text variant="muted" className="text-sm">
              {nowPlayingLine(status.playback.nowPlaying)}
            </Text>
          )}
        </View>
        <Switch
          accessibilityLabel="Lofi music"
          checked={status.enabled}
          onCheckedChange={(enabled) => void music.setEnabled(enabled)}
        />
      </View>

      <WrongMood music={music} status={status} />

      <View className="w-full gap-2">
        <View className="w-full flex-row items-center justify-between gap-4">
          <Text maxFontSizeMultiplier={1.5}>Music volume</Text>
          <Text maxFontSizeMultiplier={1.5} className="shrink-0 text-sm">
            {musicLevelLabel(level)}
          </Text>
        </View>
        <Slider
          accessibilityLabel="Music volume under the voice"
          disabled={!status.enabled}
          className="w-full"
          start={quietest}
          stop={loudest}
          step={1}
          value={level}
          onValueChange={(value) => void music.setMusicLevel(Math.round(value))}
        />
        <View className="w-full flex-row items-center justify-between">
          <Text variant="muted">Quieter</Text>
          {!isDefaultLevel && (
            <Button
              accessibilityLabel="Reset the music volume"
              variant="ghost"
              size="sm"
              onPress={() => void music.setMusicLevel(null)}
            >
              <Text>Reset</Text>
            </Button>
          )}
          <Text variant="muted">Louder</Text>
        </View>
      </View>

      {atmosphere && <AtmosphereControls music={music} status={status} />}

      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5}>Off in the car</Text>
          <Text variant="muted">
            {atmosphere
              ? "No music or sounds through CarPlay"
              : "No music through CarPlay"}
          </Text>
        </View>
        <Switch
          accessibilityLabel="Lofi music off in the car"
          checked={status.mutedInCar}
          onCheckedChange={(muted) => void music.setMutedInCar(muted)}
        />
      </View>
    </View>
  )
}

/**
 * "Wrong mood": the music moves to the engine's next guess, then you can pick
 * the mood yourself. Every tap is logged for the listening test.
 */
function WrongMood({
  music,
  status,
}: Props & { status: NonNullable<LofiMusic["status"]> }) {
  const [message, setMessage] = useState<string | null>(null)
  const [picking, setPicking] = useState(false)
  const [busy, setBusy] = useState(false)
  const playing = canMarkWrongMood(status)
  const counts = status.feedback ? moodFeedbackLine(status.feedback) : null
  const moods = status.library.moods.filter(
    (mood) => mood.tracks > 0 && mood.mood !== status.playback.musicMood,
  )

  async function mark(mood: string | null) {
    setBusy(true)
    try {
      const result = await music.markWrongMood(mood)
      if (result) {
        setMessage(
          mood
            ? `Switched to ${result.chosen} music.`
            : wrongMoodResult(result),
        )
        setPicking(mood === null)
      } else {
        setMessage("Nothing to change right now.")
        setPicking(false)
      }
    } finally {
      setBusy(false)
    }
  }

  if (!playing && !message && !counts) return null

  return (
    <View className="w-full gap-2">
      <View className="w-full flex-row items-center justify-between gap-4">
        <Button
          accessibilityLabel="The music's mood is wrong. Try another"
          accessibilityHint="Moves the music to another mood and notes the miss"
          variant="secondary"
          size="sm"
          disabled={!playing || busy}
          onPress={() => void mark(null)}
        >
          <Text>Wrong mood</Text>
        </Button>
        {playing && !picking && (
          <Button
            accessibilityLabel="Pick the music's mood"
            variant="ghost"
            size="sm"
            disabled={busy}
            onPress={() => {
              setPicking(true)
            }}
          >
            <Text>Pick a mood</Text>
          </Button>
        )}
      </View>
      {message && <Text variant="muted">{message}</Text>}
      {playing && picking && (
        <View className="w-full flex-row flex-wrap gap-2">
          {moods.map((mood) => (
            <Button
              key={mood.mood}
              accessibilityLabel={`Play ${mood.mood} music`}
              variant="outline"
              size="sm"
              disabled={busy}
              onPress={() => void mark(mood.mood)}
            >
              <Text>{moodName(mood.mood)}</Text>
            </Button>
          ))}
        </View>
      )}
      {counts && (
        <Text variant="muted" className="text-sm">
          {counts}
        </Text>
      )}
    </View>
  )
}

/** The atmosphere sounds: on or off, and their volume. */
function AtmosphereControls({
  music,
  status,
}: Props & { status: NonNullable<LofiMusic["status"]> }) {
  const atmosphere = status.atmosphere
  if (!atmosphere) return null
  const [quietest = -40, loudest = -14] = atmosphere.levelRange
  const level = Math.min(loudest, Math.max(quietest, atmosphere.levelDB))
  const isDefaultLevel =
    Math.round(level) === Math.round(atmosphere.defaultLevelDB)
  const defaultIntensity = atmosphere.defaultIntensity ?? 0.75
  const intensity = Math.min(
    1,
    Math.max(0, atmosphere.intensity ?? defaultIntensity),
  )
  const isDefaultIntensity =
    Math.round(intensity * 20) === Math.round(defaultIntensity * 20)

  return (
    <View className="w-full gap-2">
      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5} className="text-lg">
            Atmosphere sounds
          </Text>
          <Text variant="muted">{describeAtmosphere(status)}</Text>
        </View>
        <Switch
          accessibilityLabel="Atmosphere sounds"
          checked={atmosphere.enabled}
          onCheckedChange={(enabled) =>
            void music.setAtmosphereEnabled(enabled)
          }
        />
      </View>
      <View className="w-full flex-row items-center justify-between gap-4">
        <Text maxFontSizeMultiplier={1.5}>Sounds volume</Text>
        <Text maxFontSizeMultiplier={1.5} className="shrink-0 text-sm">
          {musicLevelLabel(level)}
        </Text>
      </View>
      <Slider
        accessibilityLabel="Atmosphere sounds volume under the voice"
        disabled={!atmosphere.enabled}
        className="w-full"
        start={quietest}
        stop={loudest}
        step={1}
        value={level}
        onValueChange={(value) =>
          void music.setAtmosphereLevel(Math.round(value))
        }
      />
      <View className="w-full flex-row items-center justify-between">
        <Text variant="muted">Quieter</Text>
        {!isDefaultLevel && (
          <Button
            accessibilityLabel="Reset the atmosphere sounds volume"
            variant="ghost"
            size="sm"
            onPress={() => void music.setAtmosphereLevel(null)}
          >
            <Text>Reset</Text>
          </Button>
        )}
        <Text variant="muted">Louder</Text>
      </View>
      <View className="w-full flex-row items-center justify-between gap-4">
        <Text maxFontSizeMultiplier={1.5}>How much is going on</Text>
        <Text maxFontSizeMultiplier={1.5} className="shrink-0 text-sm">
          {intensityLabel(intensity)}
        </Text>
      </View>
      <Slider
        accessibilityLabel="How much is going on in the atmosphere"
        disabled={!atmosphere.enabled}
        className="w-full"
        start={0}
        stop={1}
        step={0.05}
        value={intensity}
        onValueChange={(value) =>
          void music.setAtmosphereIntensity(Math.round(value * 20) / 20)
        }
      />
      <View className="w-full flex-row items-center justify-between">
        <Text variant="muted">Just the main sound</Text>
        {!isDefaultIntensity && (
          <Button
            accessibilityLabel="Reset how much is going on in the atmosphere"
            variant="ghost"
            size="sm"
            onPress={() => void music.setAtmosphereIntensity(null)}
          >
            <Text>Reset</Text>
          </Button>
        )}
        <Text variant="muted">The whole scene</Text>
      </View>
    </View>
  )
}
