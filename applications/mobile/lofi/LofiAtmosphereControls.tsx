// LOFI-FORK: the atmosphere's controls, shared by the player's panel and
// Settings (see FORK.md).
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import {
  describeAtmosphere,
  intensityLabel,
  levelLabel,
} from "@/modules/lofi-score/status"

import { type LofiAtmosphere } from "./useLofiAtmosphere"

type Props = {
  atmosphere: LofiAtmosphere
}

/** On and off, the sounds' volume under the voice, how much is going on, and the car. */
export function LofiAtmosphereControls({ atmosphere }: Props) {
  const { status } = atmosphere
  if (!status) {
    return (
      <Text variant="muted" className="py-4">
        Loading…
      </Text>
    )
  }
  const sounds = status.atmosphere
  const [quietest = -40, loudest = -4] = sounds.levelRange
  const level = Math.min(loudest, Math.max(quietest, sounds.levelDB))
  const isDefaultLevel = Math.round(level) === Math.round(sounds.defaultLevelDB)
  const intensity = Math.min(1, Math.max(0, sounds.intensity))
  const isDefaultIntensity =
    Math.round(intensity * 20) === Math.round(sounds.defaultIntensity * 20)

  return (
    <View className="w-full gap-5">
      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5} className="text-lg">
            Atmosphere sounds
          </Text>
          <Text variant="muted">{describeAtmosphere(status)}</Text>
        </View>
        <Switch
          accessibilityLabel="Atmosphere sounds"
          checked={sounds.enabled}
          disabled={!sounds.available}
          onCheckedChange={(enabled) => void atmosphere.setEnabled(enabled)}
        />
      </View>

      <View className="w-full gap-2">
        <View className="w-full flex-row items-center justify-between gap-4">
          <Text maxFontSizeMultiplier={1.5}>Sounds volume</Text>
          <Text maxFontSizeMultiplier={1.5} className="shrink-0 text-sm">
            {levelLabel(level)}
          </Text>
        </View>
        <Slider
          accessibilityLabel="Sounds volume under the voice"
          disabled={!sounds.enabled}
          className="w-full"
          start={quietest}
          stop={loudest}
          step={1}
          value={level}
          onValueChange={(value) => void atmosphere.setLevel(Math.round(value))}
        />
        <View className="w-full flex-row items-center justify-between">
          <Text variant="muted">Quieter</Text>
          {!isDefaultLevel && (
            <Button
              accessibilityLabel="Reset the sounds volume"
              variant="ghost"
              size="sm"
              onPress={() => void atmosphere.setLevel(null)}
            >
              <Text>Reset</Text>
            </Button>
          )}
          <Text variant="muted">Louder</Text>
        </View>
      </View>

      <View className="w-full gap-2">
        <View className="w-full flex-row items-center justify-between gap-4">
          <Text maxFontSizeMultiplier={1.5}>How much is going on</Text>
          <Text maxFontSizeMultiplier={1.5} className="shrink-0 text-sm">
            {intensityLabel(intensity)}
          </Text>
        </View>
        <Slider
          accessibilityLabel="How much is going on in the atmosphere"
          disabled={!sounds.enabled}
          className="w-full"
          start={0}
          stop={1}
          step={0.05}
          value={intensity}
          onValueChange={(value) =>
            void atmosphere.setIntensity(Math.round(value * 20) / 20)
          }
        />
        <View className="w-full flex-row items-center justify-between">
          <Text variant="muted">Just the main sound</Text>
          {!isDefaultIntensity && (
            <Button
              accessibilityLabel="Reset how much is going on in the atmosphere"
              variant="ghost"
              size="sm"
              onPress={() => void atmosphere.setIntensity(null)}
            >
              <Text>Reset</Text>
            </Button>
          )}
          <Text variant="muted">The whole scene</Text>
        </View>
      </View>

      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5}>Off in the car</Text>
          <Text variant="muted">No sounds through CarPlay</Text>
        </View>
        <Switch
          accessibilityLabel="Atmosphere sounds off in the car"
          checked={status.mutedInCar}
          onCheckedChange={(muted) => void atmosphere.setMutedInCar(muted)}
        />
      </View>
    </View>
  )
}
