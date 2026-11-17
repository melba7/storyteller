// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import {
  MARK_PLAYED_CHOICES,
  SKIP_CHOICES,
  markPlayedLabel,
  secondsLabel,
} from "@/modules/podcasts/playbackSettings"
import {
  BOOST_BODY,
  BOOST_CHOICES,
  TRIM_BODY,
  TRIM_CHOICES,
  boostLabel,
  trimLabel,
} from "@/modules/podcasts/sound"

import {
  updatePlaybackSettings,
  usePlaybackSettings,
} from "./usePlaybackSettings"

/** Profile's Playback section: skip amounts, headphone buttons, played early, rewind. */
export function PlaybackSection() {
  const settings = usePlaybackSettings()
  return (
    <View>
      <Text className="text-muted-foreground pt-6 pb-1 text-sm font-semibold uppercase">
        Playback
      </Text>
      <Choices
        title="Skip back"
        choices={SKIP_CHOICES}
        selected={settings.skipBack}
        label={secondsLabel}
        onChoose={(skipBack) => updatePlaybackSettings({ skipBack })}
      />
      <Choices
        title="Skip forward"
        choices={SKIP_CHOICES}
        selected={settings.skipForward}
        label={secondsLabel}
        onChoose={(skipForward) => updatePlaybackSettings({ skipForward })}
      />
      <Choices
        title="Headphones' next button"
        body="Previous always skips back."
        choices={["skip", "nextEpisode"] as const}
        selected={settings.headphoneNext}
        label={(value) => (value === "skip" ? "Skip ahead" : "Next in Up Next")}
        onChoose={(headphoneNext) => updatePlaybackSettings({ headphoneNext })}
      />
      <Choices
        title="Mark played when this much is left"
        choices={MARK_PLAYED_CHOICES}
        selected={settings.markPlayedWhenLeft}
        label={markPlayedLabel}
        onChoose={(markPlayedWhenLeft) =>
          updatePlaybackSettings({ markPlayedWhenLeft })
        }
      />
      <Choices
        title="Volume boost"
        body={BOOST_BODY}
        choices={BOOST_CHOICES}
        selected={settings.voiceBoost}
        label={boostLabel}
        onChoose={(voiceBoost) => updatePlaybackSettings({ voiceBoost })}
      />
      <Choices
        title="Trim silence"
        body={TRIM_BODY}
        choices={TRIM_CHOICES}
        selected={settings.trimSilence}
        label={trimLabel}
        onChoose={(trimSilence) => updatePlaybackSettings({ trimSilence })}
      />
      <View className="border-border flex-row items-center gap-3 border-b py-3">
        <View className="flex-1">
          <Text className="font-semibold">Go back after a long pause</Text>
          <Text className="text-muted-foreground text-sm">
            3 seconds after a 5-minute pause, 10 seconds after an hour.
          </Text>
        </View>
        <Switch
          accessibilityLabel="Go back after a long pause"
          checked={settings.rewindAfterPause}
          onCheckedChange={(rewindAfterPause) =>
            updatePlaybackSettings({ rewindAfterPause })
          }
        />
      </View>
    </View>
  )
}

function Choices<T extends string | number>({
  title,
  body,
  choices,
  selected,
  label,
  onChoose,
}: {
  title: string
  body?: string
  choices: readonly T[]
  selected: T
  label: (choice: T) => string
  onChoose: (choice: T) => void
}) {
  return (
    <View className="border-border gap-2 border-b py-3">
      <Text className="font-semibold">{title}</Text>
      {body ? (
        <Text className="text-muted-foreground text-sm">{body}</Text>
      ) : null}
      <View className="flex-row flex-wrap gap-2">
        {choices.map((choice) => (
          <Pressable
            key={choice}
            className={`min-h-11 justify-center rounded-full px-4 ${
              choice === selected ? "bg-primary" : "bg-secondary"
            }`}
            accessibilityRole="button"
            accessibilityLabel={`${title}, ${label(choice)}`}
            accessibilityState={{ selected: choice === selected }}
            onPress={() => onChoose(choice)}
          >
            <Text
              className={
                choice === selected
                  ? "text-primary-foreground"
                  : "text-foreground"
              }
            >
              {label(choice)}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  )
}
