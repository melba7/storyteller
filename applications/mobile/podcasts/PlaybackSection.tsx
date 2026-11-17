// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import {
  HEADPHONE_NEXT_CHOICES,
  MARK_PLAYED_CHOICES,
  SKIP_CHOICES,
  headphoneNextLabel,
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

import { ROW, SettingsGroup, SwitchRow } from "./SettingsGroup"
import {
  updatePlaybackSettings,
  usePlaybackSettings,
} from "./usePlaybackSettings"

/** Profile's Playback section: skip amounts, headphone buttons, played early, rewind. */
export function PlaybackSection() {
  const settings = usePlaybackSettings()
  return (
    <SettingsGroup title="Playback">
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
        body="Previous always skips back. Next chapter skips ahead where an episode has no chapters."
        choices={HEADPHONE_NEXT_CHOICES}
        selected={settings.headphoneNext}
        label={headphoneNextLabel}
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
      <SwitchRow
        title="Go back after a long pause"
        body="3 seconds after a 5-minute pause, 10 seconds after an hour."
        checked={settings.rewindAfterPause}
        onChange={(rewindAfterPause) =>
          updatePlaybackSettings({ rewindAfterPause })
        }
      />
    </SettingsGroup>
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
    <View className={`${ROW} gap-2 py-3`}>
      <Text className="font-semibold">{title}</Text>
      {body ? (
        <Text className="text-muted-foreground text-sm">{body}</Text>
      ) : null}
      <View className="flex-row flex-wrap gap-2">
        {choices.map((choice) => (
          <Pressable
            key={choice}
            className={`min-h-11 justify-center rounded-full px-4 ${
              choice === selected ? "bg-primary" : "bg-foreground/10"
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
