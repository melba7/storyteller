// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useEffect, useState } from "react"
import { View } from "react-native"
import { Gesture, GestureDetector } from "react-native-gesture-handler"
import Animated, {
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withTiming,
} from "react-native-reanimated"
import { scheduleOnRN } from "react-native-worklets"

import { Text } from "@/components/ui/text"
import { type AdMark } from "@/modules/podcasts/ads"
import {
  clampPosition,
  formatTime,
  timeLeft,
} from "@/modules/podcasts/playbackRules"
import {
  barFraction,
  positionAt,
  progressFraction,
} from "@/modules/podcasts/playerLook"

import { pick } from "./haptics"

interface Props {
  position: number
  duration: number | null
  /** Called once, where the listener lets go or taps. */
  onSeek: (seconds: number) => void
  /** Where the ads are, as shares of the bar. */
  marks?: readonly AdMark[]
}

const THUMB_MAX = 20
const THUMB_REST = 14
const TRACK_REST = 4
const TRACK_TOUCHED = 8
const GROW_MS = 150

/**
 * The seek bar: time played on the left, time left on the right. Drag it or tap anywhere on
 * it. While a finger is down the bar shows the finger's place, and the track and thumb grow;
 * the player only moves when it lifts.
 */
export function SeekBar({ position, duration, onSeek, marks = [] }: Props) {
  const width = useSharedValue(1)
  const [trackWidth, setTrackWidth] = useState(0)
  // The place under the finger, from 0 to 1, or null when nobody is touching the bar.
  const [touch, setTouch] = useState<number | null>(null)
  const known = duration !== null && duration > 0
  const reduceMotion = useReducedMotion()
  const grow = useSharedValue(0)
  const touched = touch !== null
  useEffect(() => {
    grow.set(
      withTiming(touched ? 1 : 0, { duration: reduceMotion ? 0 : GROW_MS }),
    )
  }, [touched, reduceMotion, grow])
  const trackStyle = useAnimatedStyle(() => ({
    height: TRACK_REST + (TRACK_TOUCHED - TRACK_REST) * grow.get(),
  }))
  const thumbStyle = useAnimatedStyle(() => {
    const size = THUMB_REST + (THUMB_MAX - THUMB_REST) * grow.get()
    return { width: size, height: size }
  })

  function move(fraction: number) {
    setTouch(fraction)
  }

  function finish(fraction: number) {
    setTouch(null)
    pick()
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
            text: known
              ? `${formatTime(shown)} played, ${formatTime(duration - shown)} left`
              : `${formatTime(shown)} played, unknown length`,
          }}
          accessibilityActions={[{ name: "increment" }, { name: "decrement" }]}
          onAccessibilityAction={(event) => {
            const step = event.nativeEvent.actionName === "increment" ? 15 : -15
            onSeek(clampPosition(position + step, duration))
          }}
          onLayout={(event) => {
            width.set(event.nativeEvent.layout.width)
            setTrackWidth(event.nativeEvent.layout.width)
          }}
        >
          <Animated.View
            className="overflow-hidden rounded-full bg-white/25"
            style={trackStyle}
          >
            <View
              className="h-full rounded-full bg-white"
              style={{ width: `${fraction * 100}%` }}
            />
            {marks.map((mark) => (
              <View
                key={mark.left}
                className={
                  mark.skipped
                    ? "absolute h-full bg-amber-300"
                    : "absolute h-full bg-amber-300/40"
                }
                style={{
                  left: `${mark.left * 100}%`,
                  width: `${Math.max(mark.width * 100, 0.6)}%`,
                }}
              />
            ))}
          </Animated.View>
          <View
            className="absolute items-center justify-center"
            style={{
              width: THUMB_MAX,
              height: THUMB_MAX,
              left: Math.max(0, fraction * trackWidth - THUMB_MAX / 2),
            }}
          >
            <Animated.View
              className="rounded-full bg-white"
              style={thumbStyle}
            />
          </View>
        </View>
      </GestureDetector>
      <View className="flex-row justify-between">
        <Text
          className="text-sm text-white/70"
          style={{ fontVariant: ["tabular-nums"] }}
        >
          {formatTime(shown)}
        </Text>
        <Text
          className="text-sm text-white/70"
          style={{ fontVariant: ["tabular-nums"] }}
        >
          {timeLeft(shown, duration)}
        </Text>
      </View>
    </View>
  )
}
