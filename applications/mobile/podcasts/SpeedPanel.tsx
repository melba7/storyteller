// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Minus, Plus } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { speedLabel, stepSpeed } from "@/modules/podcasts/playbackRules"

const PRESETS = [1, 1.2, 1.5, 2]

interface Props {
  rate: number
  onChange: (rate: number) => void
}

/** The speed panel: minus and plus in steps of 0.1, and a few presets. */
export function SpeedPanel({ rate, onChange }: Props) {
  return (
    <View className="gap-4 rounded-2xl bg-black/35 p-4">
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
          className="text-2xl font-semibold text-white"
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
            className={`flex-1 items-center rounded-full py-2 ${
              rate === preset ? "bg-white" : "bg-white/15 active:bg-white/25"
            }`}
            accessibilityRole="button"
            accessibilityLabel={`Speed ${speedLabel(preset)}`}
            accessibilityState={{ selected: rate === preset }}
            onPress={() => onChange(preset)}
          >
            <Text
              className={rate === preset ? "text-black" : "text-white"}
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
