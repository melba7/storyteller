// LOFI-FORK: the atmosphere's controls, shared by the player's panel and
// Settings (see FORK.md).
import { View } from "react-native"

import { GroupedRow, GroupedSection } from "@/apple-look/GroupedList"
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
  /** A muted heading above the card. */
  title?: string
  /** Muted explanatory text under the card. */
  footer?: string
}

/** On and off, the sounds' volume under the voice, how much is going on, and the car. */
export function LofiAtmosphereControls({ atmosphere, title, footer }: Props) {
  const { status } = atmosphere
  if (!status) {
    return (
      <Text variant="muted" className="py-4 text-[15px]">
        Loading…
      </Text>
    )
  }
  const sounds = status.atmosphere
  const [quietest = -40, loudest = 0] = sounds.levelRange
  const level = Math.min(loudest, Math.max(quietest, sounds.levelDB))
  const isDefaultLevel = Math.round(level) === Math.round(sounds.defaultLevelDB)
  const intensity = Math.min(1, Math.max(0, sounds.intensity))
  const isDefaultIntensity =
    Math.round(intensity * 20) === Math.round(sounds.defaultIntensity * 20)

  return (
    <GroupedSection title={title} footer={footer}>
      <GroupedRow
        title="Atmosphere sounds"
        subtitle={describeAtmosphere(status)}
        trailing={
          <Switch
            accessibilityLabel="Atmosphere sounds"
            checked={sounds.enabled}
            disabled={!sounds.available}
            onCheckedChange={(enabled) => void atmosphere.setEnabled(enabled)}
          />
        }
      />
      <GroupedRow
        title="Sounds volume"
        value={levelLabel(level)}
        className="pb-2"
      >
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
          <Text className="text-muted-foreground text-[13px]">Quieter</Text>
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
          <Text className="text-muted-foreground text-[13px]">Louder</Text>
        </View>
      </GroupedRow>
      <GroupedRow
        title="How much is going on"
        value={intensityLabel(intensity)}
        className="pb-2"
      >
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
          <Text className="text-muted-foreground text-[13px]">
            Just the main sound
          </Text>
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
          <Text className="text-muted-foreground text-[13px]">
            The whole scene
          </Text>
        </View>
      </GroupedRow>
      <GroupedRow
        title="Off in the car"
        subtitle="No sounds through CarPlay"
        trailing={
          <Switch
            accessibilityLabel="Atmosphere sounds off in the car"
            checked={status.mutedInCar}
            onCheckedChange={(muted) => void atmosphere.setMutedInCar(muted)}
          />
        }
      />
    </GroupedSection>
  )
}
