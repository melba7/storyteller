// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { type ReactNode, useEffect, useState } from "react"
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
import { useSheet } from "./playerSheetContext"

interface Props {
  position: number
  duration: number | null
  /** Called once, where the listener lets go or taps. */
  onSeek: (seconds: number) => void
  /** Where the ads are, as shares of the bar. */
  marks?: readonly AdMark[]
  /** Shown between the two times (the chapter playing). */
  center?: ReactNode
}

const TRACK_REST = 7
const TRACK_TOUCHED = 16
const GROW_MS = 150

/**
 * The seek bar, a thick rounded bar: time played on the left, time left on the right (and the
 * chapter between them). Drag it or tap anywhere on it. While a finger is down the bar shows
 * the finger's place and grows; the player only moves when it lifts.
 */
export function SeekBar({
  position,
  duration,
  onSeek,
  marks = [],
  center,
}: Props) {
  const sheet = useSheet()
  const width = useSharedValue(1)
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
          }}
        >
          <Animated.View
            className="overflow-hidden rounded-full"
            style={[trackStyle, { backgroundColor: sheet.rest }]}
          >
            <View
              className="h-full rounded-full"
              style={{
                width: `${fraction * 100}%`,
                backgroundColor: sheet.fill,
              }}
            />
            {marks.map((mark) => (
              <View
                key={mark.left}
                className={
                  mark.skipped && !mark.unsure
                    ? "absolute h-full bg-amber-300"
                    : "absolute h-full bg-amber-300/40"
                }
                // An outline in the sheet's ink keeps the mark visible on a yellow or light sheet.
                style={{
                  borderWidth: 1,
                  borderColor: sheet.ink,
                  left: `${mark.left * 100}%`,
                  width: `${Math.max(mark.width * 100, 0.6)}%`,
                }}
              />
            ))}
          </Animated.View>
        </View>
      </GestureDetector>
      <View className="flex-row items-center justify-between gap-3">
        <Text
          className="text-sm font-semibold"
          style={{ fontVariant: ["tabular-nums"], color: sheet.muted }}
        >
          {formatTime(shown)}
        </Text>
        {center ?? <View className="flex-1" />}
        <Text
          className="text-sm font-semibold"
          style={{ fontVariant: ["tabular-nums"], color: sheet.muted }}
        >
          {timeLeft(shown, duration).replace("-", "\u2212")}
        </Text>
      </View>
    </View>
  )
}
