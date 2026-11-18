// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Pause, Play, RotateCcw, RotateCw } from "lucide-react-native"
import { useState } from "react"
import { ActivityIndicator, Pressable, View } from "react-native"
import { type SFSymbol } from "sf-symbols-typescript"

import { Text } from "@/components/ui/text"
import { speedLabel } from "@/modules/podcasts/playbackRules"
import { skipLabel } from "@/modules/podcasts/playbackSettings"
import { transportSizes } from "@/modules/podcasts/playerFrame"
import { player, type usePlayer } from "@/modules/podcasts/playerInstance"
import { skipSymbol } from "@/modules/podcasts/playerLook"

import { SFIcon } from "./SFIcon"
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
  // The row's own width, so a 320 pt screen gets smaller boxes instead of an overflowing row.
  const [rowWidth, setRowWidth] = useState<number | null>(null)
  const sizes = transportSizes(rowWidth)
  return (
    <View
      className="w-full flex-row items-center justify-between"
      onLayout={(event) => setRowWidth(event.nativeEvent.layout.width)}
    >
      <View className="items-start" style={{ width: sizes.side }}>
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
            maxFontSizeMultiplier={1.3}
          >
            {speedLabel(view.rate).replace("x", "×").replace(".0", "")}
          </Text>
        </Pressable>
      </View>
      <SkipButton
        label={skipLabel("back", skipBack)}
        symbol={skipSymbol("back", skipBack)}
        seconds={skipBack}
        box={sizes.skip}
        icon={RotateCcw}
        onPress={() => {
          tap()
          void player.skip(-skipBack)
        }}
      />
      <Pressable
        className="items-center justify-center active:opacity-60"
        style={{ width: sizes.play, height: sizes.play }}
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
          <SFIcon
            name={view.isPlaying ? "pause.fill" : "play.fill"}
            size={56}
            color={sheet.ink}
            fallback={view.isPlaying ? Pause : Play}
            filled
          />
        )}
      </Pressable>
      <SkipButton
        label={skipLabel("ahead", skipForward)}
        symbol={skipSymbol("ahead", skipForward)}
        seconds={skipForward}
        box={sizes.skip}
        icon={RotateCw}
        onPress={() => {
          tap()
          void player.skip(skipForward)
        }}
      />
      <View className="items-end" style={{ width: sizes.side }}>
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
  symbol,
  seconds,
  box,
  icon,
  onPress,
}: {
  label: string
  symbol: SFSymbol
  seconds: number
  /** The side of the touch box. */
  box: number
  icon: typeof RotateCcw
  onPress: () => void
}) {
  const sheet = useSheet()
  return (
    <Pressable
      className="items-center justify-center active:opacity-60"
      style={{ width: box, height: box }}
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
    >
      <SFIcon
        name={symbol}
        size={40}
        color={sheet.ink}
        fallback={icon}
        badge={seconds}
      />
    </Pressable>
  )
}
