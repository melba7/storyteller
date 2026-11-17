// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useState } from "react"
import { View } from "react-native"
import { Gesture, GestureDetector } from "react-native-gesture-handler"
import { useSharedValue } from "react-native-reanimated"
import { scheduleOnRN } from "react-native-worklets"

import { Text } from "@/components/ui/text"
import { formatTime, timeLeft } from "@/modules/podcasts/playback"
import {
  barFraction,
  positionAt,
  progressFraction,
} from "@/modules/podcasts/playerLook"

interface Props {
  position: number
  duration: number | null
  /** Called once, where the listener lets go or taps. */
  onSeek: (seconds: number) => void
}

const THUMB = 14

/**
 * The seek bar: time played on the left, time left on the right. Drag it or tap anywhere on
 * it. While a finger is down the bar shows the finger's place; the player only moves when it
 * lifts.
 */
export function SeekBar({ position, duration, onSeek }: Props) {
  const width = useSharedValue(1)
  const [trackWidth, setTrackWidth] = useState(0)
  // The place under the finger, from 0 to 1, or null when nobody is touching the bar.
  const [touch, setTouch] = useState<number | null>(null)
  const known = duration !== null && duration > 0

  function move(fraction: number) {
    setTouch(fraction)
  }

  function finish(fraction: number) {
    setTouch(null)
    onSeek(positionAt(fraction, duration))
  }

  const pan = Gesture.Pan()
    .enabled(known)
    .activeOffsetX([-6, 6])
    .failOffsetY([-12, 12])
    .onBegin((event) => {
      "worklet"
      scheduleOnRN(move, barFraction(event.x, width.get()))
    })
    .onUpdate((event) => {
      "worklet"
      scheduleOnRN(move, barFraction(event.x, width.get()))
    })
    .onEnd((event) => {
      "worklet"
      scheduleOnRN(finish, barFraction(event.x, width.get()))
    })
    .onFinalize((_event, success) => {
      "worklet"
      if (!success) scheduleOnRN(setTouch, null)
    })

  const tap = Gesture.Tap()
    .enabled(known)
    .onEnd((event) => {
      "worklet"
      scheduleOnRN(finish, barFraction(event.x, width.get()))
    })

  const fraction = touch ?? progressFraction(position, duration)
  const shown = touch === null ? position : positionAt(touch, duration)

  return (
    <View className="w-full">
      <GestureDetector gesture={Gesture.Race(pan, tap)}>
        <View
          className="h-10 justify-center"
          accessibilityRole="adjustable"
          accessibilityLabel="Seek bar"
          accessibilityValue={{
            text: `${formatTime(shown)}, ${timeLeft(shown, duration)} left`,
          }}
          accessibilityActions={[{ name: "increment" }, { name: "decrement" }]}
          onAccessibilityAction={(event) => {
            const step = event.nativeEvent.actionName === "increment" ? 15 : -15
            onSeek(Math.max(0, position + step))
          }}
          onLayout={(event) => {
            width.set(event.nativeEvent.layout.width)
            setTrackWidth(event.nativeEvent.layout.width)
          }}
        >
          <View className="h-1 overflow-hidden rounded-full bg-white/25">
            <View
              className="h-1 rounded-full bg-white"
              style={{ width: `${fraction * 100}%` }}
            />
          </View>
          <View
            className="absolute rounded-full bg-white"
            style={{
              width: THUMB,
              height: THUMB,
              left: Math.max(0, fraction * trackWidth - THUMB / 2),
            }}
          />
        </View>
      </GestureDetector>
      <View className="flex-row justify-between">
        <Text className="text-sm text-white/70">{formatTime(shown)}</Text>
        <Text className="text-sm text-white/70">
          {timeLeft(shown, duration)}
        </Text>
      </View>
    </View>
  )
}
