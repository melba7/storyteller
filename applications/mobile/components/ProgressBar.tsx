import { Host } from "@expo/ui"
import { ProgressView } from "@expo/ui/swift-ui"
import {
  accessibilityLabel as swiftAccessibilityLabel,
  progressViewStyle,
  tint,
} from "@expo/ui/swift-ui/modifiers"
import { useState } from "react"
import { Platform, View } from "react-native"
import { Gesture, GestureDetector } from "react-native-gesture-handler"
import { scheduleOnRN } from "react-native-worklets"
import { useCSSVariable } from "uniwind"

import { cn } from "@/lib/utils"

import { Slider } from "./ui/slider"

type Props = {
  accessibilityLabel?: string | undefined
  className?: string | undefined
  start?: number
  step?: number
  stop?: number
  progress: number
  onProgressChange?: ((newProgress: number) => void) | undefined
  onPanStart?: (() => void) | undefined
  onPanStop?: (() => void) | undefined
  /** Draws Apple's slim rounded bar (the players) instead of the platform's. */
  slim?: boolean
  /** Classes for the slim bar's track and its filled part. */
  trackClassName?: string | undefined
  fillClassName?: string | undefined
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

function ReadOnlyProgressBar({
  accessibilityLabel,
  className,
  progress,
  start,
  stop,
}: Required<Pick<Props, "progress" | "start" | "stop">> &
  Pick<Props, "accessibilityLabel" | "className">) {
  const primaryColor = useCSSVariable("--color-primary") as string
  const hasUsableRange = stop > start
  const boundedProgress = hasUsableRange ? clamp(progress, start, stop) : start
  const progressValue = hasUsableRange
    ? (boundedProgress - start) / (stop - start)
    : 0

  const progressBarProps = {
    accessibilityLabel,
    accessibilityRole: "progressbar" as const,
    accessibilityValue: hasUsableRange
      ? { min: start, max: stop, now: boundedProgress }
      : undefined,
  }

  if (Platform.OS === "android") {
    return (
      <View
        {...progressBarProps}
        className={cn("relative min-h-8 justify-center", className)}
      >
        <View className="bg-secondary h-4 rounded-xl">
          <View
            className="bg-primary h-full rounded-xl"
            style={{ width: `${progressValue * 100}%` }}
          />
        </View>
      </View>
    )
  }

  return (
    <View
      {...progressBarProps}
      className={cn("relative min-h-8 justify-center", className)}
    >
      <Host ignoreSafeArea="all" className="self-stretch">
        <ProgressView
          value={progressValue}
          modifiers={[
            tint(primaryColor),
            progressViewStyle("linear"),
            ...(accessibilityLabel
              ? [swiftAccessibilityLabel(accessibilityLabel)]
              : []),
          ]}
        />
      </Host>
    </View>
  )
}

function SlimProgressBar({
  accessibilityLabel,
  className,
  start,
  step,
  stop,
  progress,
  trackClassName,
  fillClassName,
  onProgressChange,
  onPanStart,
  onPanStop,
}: Required<Pick<Props, "progress" | "start" | "stop" | "step">> &
  Omit<Props, "progress" | "start" | "stop" | "step" | "slim">) {
  const [width, setWidth] = useState(0)
  const hasUsableRange = stop > start
  const boundedProgress = hasUsableRange ? clamp(progress, start, stop) : start
  const fraction = hasUsableRange
    ? (boundedProgress - start) / (stop - start)
    : 0

  const seekToX = (x: number) => {
    if (!onProgressChange || !hasUsableRange || width <= 0) return
    const raw = start + clamp(x / width, 0, 1) * (stop - start)
    const aligned = step > 0 ? Math.round((raw - start) / step) * step + start : raw
    onProgressChange(clamp(aligned, start, stop))
  }
  const jump = Math.max(step, (stop - start) / 20)

  // Seeking starts only once a sideways drag does, like the old slider,
  // so a stray tap on the bar never moves the position.
  const gesture = Gesture.Pan()
    .enabled(!!onProgressChange)
    .activeOffsetX([-4, 4])
    .onStart((event) => {
      "worklet"
      if (onPanStart) scheduleOnRN(onPanStart)
      scheduleOnRN(seekToX, event.x)
    })
    .onUpdate((event) => {
      "worklet"
      scheduleOnRN(seekToX, event.x)
    })
    .onEnd(() => {
      "worklet"
      if (onPanStop) scheduleOnRN(onPanStop)
    })

  return (
    <GestureDetector gesture={gesture}>
      <View
        accessibilityLabel={accessibilityLabel}
        accessibilityRole={onProgressChange ? "adjustable" : "progressbar"}
        accessibilityValue={
          hasUsableRange
            ? { min: start, max: stop, now: boundedProgress }
            : undefined
        }
        accessibilityActions={
          onProgressChange
            ? [{ name: "increment" }, { name: "decrement" }]
            : undefined
        }
        onAccessibilityAction={(event) => {
          if (!onProgressChange) return
          const delta = event.nativeEvent.actionName === "increment" ? jump : -jump
          onProgressChange(clamp(boundedProgress + delta, start, stop))
        }}
        className={cn("justify-center", className)}
        onLayout={(event) => {
          setWidth(event.nativeEvent.layout.width)
        }}
      >
        <View
          className={cn("bg-foreground/15 h-1.5 overflow-hidden rounded-full", trackClassName)}
        >
          <View
            className={cn("bg-foreground/60 h-full rounded-full", fillClassName)}
            style={{ width: `${fraction * 100}%` }}
          />
        </View>
      </View>
    </GestureDetector>
  )
}

export function ProgressBar({
  accessibilityLabel,
  className,
  start = 0,
  step = 1,
  stop = 100,
  progress,
  onProgressChange,
  onPanStart,
  onPanStop,
  slim,
  trackClassName,
  fillClassName,
}: Props) {
  if (slim) {
    return (
      <SlimProgressBar
        accessibilityLabel={accessibilityLabel}
        className={className}
        start={start}
        step={step}
        stop={stop}
        progress={progress}
        trackClassName={trackClassName}
        fillClassName={fillClassName}
        onProgressChange={onProgressChange}
        onPanStart={onPanStart}
        onPanStop={onPanStop}
      />
    )
  }

  if (onProgressChange) {
    return (
      <View {...(className && { className })}>
        <Slider
          accessibilityLabel={accessibilityLabel}
          start={start}
          stop={stop}
          step={step}
          value={progress}
          onValueChange={onProgressChange}
          onPanStart={onPanStart}
          onPanStop={onPanStop}
        />
      </View>
    )
  }

  return (
    <ReadOnlyProgressBar
      accessibilityLabel={accessibilityLabel}
      className={className}
      progress={progress}
      start={start}
      stop={stop}
    />
  )
}
