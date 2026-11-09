// LOFI-FORK: the lofi music's controls, shared by the player's music panel and
// Settings (see FORK.md).
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import { describeMusic, musicLevelLabel } from "@/modules/lofi-score/status"

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

  return (
    <View className="w-full gap-5">
      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5} className="text-lg">
            Lofi music
          </Text>
          <Text variant="muted">{describeMusic(status)}</Text>
        </View>
        <Switch
          accessibilityLabel="Lofi music"
          checked={status.enabled}
          onCheckedChange={(enabled) => void music.setEnabled(enabled)}
        />
      </View>

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

      <View className="w-full flex-row items-center justify-between gap-4">
        <View className="shrink gap-1">
          <Text maxFontSizeMultiplier={1.5}>Off in the car</Text>
          <Text variant="muted">No music through CarPlay</Text>
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
