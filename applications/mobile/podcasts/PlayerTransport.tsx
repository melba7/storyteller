// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Pause, Play, RotateCcw, RotateCw } from "lucide-react-native"
import { useState } from "react"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { speedLabel } from "@/modules/podcasts/playbackRules"
import { skipLabel } from "@/modules/podcasts/playbackSettings"
import { player, type usePlayer } from "@/modules/podcasts/playerInstance"

import { SleepTimerButton } from "./SleepTimerSheet"
import { SpeedSheet } from "./SpeedPanel"
import { tap } from "./haptics"
import { useSheet } from "./playerSheetContext"
import { usePlaybackSettings } from "./usePlaybackSettings"

/**
 * The transport row: speed ("1×", opens the speed sheet), skip back, a big play or pause,
 * skip forward and the sleep timer.
 */
export function PlayerTransport({
  view,
}: {
  view: ReturnType<typeof usePlayer>
}) {
  const sheet = useSheet()
  const { skipBack, skipForward } = usePlaybackSettings()
  const [showSpeed, setShowSpeed] = useState(false)
  return (
    <View className="w-full flex-row items-center justify-between">
      <View className="w-12 items-start">
        <Pressable
          className="h-11 min-w-11 justify-center active:opacity-60"
          accessibilityRole="button"
          accessibilityLabel={`Playback speed ${speedLabel(view.rate)}`}
          onPress={() => setShowSpeed(true)}
        >
          <Text
            className="text-lg font-semibold"
            style={{ fontVariant: ["tabular-nums"], color: sheet.tint }}
            numberOfLines={1}
          >
            {speedLabel(view.rate).replace("x", "×").replace(".0", "")}
          </Text>
        </Pressable>
      </View>
      <SkipButton
        label={skipLabel("back", skipBack)}
        seconds={skipBack}
        icon={RotateCcw}
        onPress={() => {
          tap()
          void player.skip(-skipBack)
        }}
      />
      <Pressable
        className="size-20 items-center justify-center active:opacity-60"
        accessibilityRole="button"
        accessibilityLabel={view.isPlaying ? "Pause" : "Play"}
        onPress={() => {
          tap()
          void player.togglePlayPause()
        }}
      >
        {view.isBuffering ? (
          <ActivityIndicator color={sheet.ink} accessibilityLabel="Buffering" />
        ) : (
          <Icon
            as={view.isPlaying ? Pause : Play}
            size={52}
            color={sheet.ink}
            fill={sheet.ink}
          />
        )}
      </Pressable>
      <SkipButton
        label={skipLabel("ahead", skipForward)}
        seconds={skipForward}
        icon={RotateCw}
        onPress={() => {
          tap()
          void player.skip(skipForward)
        }}
      />
      <View className="w-12 items-end">
        <SleepTimerButton />
      </View>
      <SpeedSheet
        visible={showSpeed}
        onClose={() => setShowSpeed(false)}
        rate={view.rate}
        onChange={(rate) => void player.setRate(rate)}
      />
    </View>
  )
}

function SkipButton({
  label,
  seconds,
  icon,
  onPress,
}: {
  label: string
  seconds: number
  icon: typeof RotateCcw
  onPress: () => void
}) {
  const sheet = useSheet()
  return (
    <Pressable
      className="size-14 items-center justify-center active:opacity-60"
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Icon as={icon} size={44} color={sheet.ink} strokeWidth={1.5} />
      <Text className="absolute text-xs font-bold" style={{ color: sheet.ink }}>
        {seconds}
      </Text>
    </Pressable>
  )
}
