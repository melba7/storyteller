// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Minus, Plus } from "lucide-react-native"
import { Modal, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { speedLabel, stepSpeed } from "@/modules/podcasts/playbackRules"

const PRESETS = [1, 1.2, 1.5, 2]

interface Props {
  rate: number
  onChange: (rate: number) => void
}

/**
 * The speed choices in a bottom sheet, like the sleep timer's, so the player page behind it
 * doesn't move. The sheet is dark whatever the theme, like the player.
 */
export function SpeedSheet({
  visible,
  onClose,
  ...panel
}: Props & { visible: boolean; onClose: () => void }) {
  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
    >
      <View className="flex-1 justify-end">
        <Pressable
          className="absolute inset-0 bg-black/50"
          accessibilityRole="button"
          accessibilityLabel="Close the speed choices"
          onPress={onClose}
        />
        <View className="pb-safe-offset-3 gap-4 rounded-t-3xl bg-neutral-900 px-6 pt-5">
          <Text className="text-lg font-semibold text-white">
            Playback speed
          </Text>
          <SpeedPanel {...panel} />
        </View>
      </View>
    </Modal>
  )
}

/** The speed panel: minus and plus in steps of 0.1, and a few presets. */
export function SpeedPanel({ rate, onChange }: Props) {
  return (
    <View className="gap-4">
      <View className="flex-row items-center justify-between">
        <Pressable
          className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
          accessibilityRole="button"
          accessibilityLabel="Slower"
          onPress={() => onChange(stepSpeed(rate, -1))}
        >
          <Icon as={Minus} size={20} className="text-white" />
        </Pressable>
        <Text
          className="text-3xl font-semibold text-white"
          style={{ fontVariant: ["tabular-nums"] }}
          accessibilityLabel={`Speed ${speedLabel(rate)}`}
        >
          {speedLabel(rate)}
        </Text>
        <Pressable
          className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
          accessibilityRole="button"
          accessibilityLabel="Faster"
          onPress={() => onChange(stepSpeed(rate, 1))}
        >
          <Icon as={Plus} size={20} className="text-white" />
        </Pressable>
      </View>
      <View className="flex-row justify-between gap-2">
        {PRESETS.map((preset) => (
          <Pressable
            key={preset}
            className={`min-h-11 flex-1 items-center justify-center rounded-full py-2 ${
              rate === preset ? "bg-white" : "bg-white/15 active:bg-white/25"
            }`}
            accessibilityRole="button"
            accessibilityLabel={`Speed ${speedLabel(preset)}`}
            accessibilityState={{ selected: rate === preset }}
            onPress={() => onChange(preset)}
          >
            <Text
              className={
                rate === preset ? "font-semibold text-black" : "text-white"
              }
              numberOfLines={1}
            >
              {speedLabel(preset)}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  )
}
