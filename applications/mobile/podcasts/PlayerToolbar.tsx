// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { List, MessageSquareQuote } from "lucide-react-native"
import { Pressable, View } from "react-native"
import { type SFSymbol } from "sf-symbols-typescript"

import { Text } from "@/components/ui/text"
import {
  SKIP_AD_ACCESSIBILITY,
  SKIP_AD_BUTTON,
  SKIP_AD_LABEL,
} from "@/modules/podcasts/skipAdLook"

import { AirPlayButton } from "./AirPlayButton"
import { type PlayerPanel } from "./PlayerPages"
import { SFIcon } from "./SFIcon"
import { pick } from "./haptics"
import { useSheet } from "./playerSheetContext"
import { pressSkipAd } from "./useMissedNote"

/**
 * The player's bottom row: Skip ad, transcript, AirPlay and the queue spread evenly, the
 * transcript and queue lit while their panel shows. Each panel button toggles its panel in place
 * of the artwork. Skip ad is a capsule with its words in it; the others are round icons.
 */
export function PlayerToolbar({
  panel,
  onPanel,
}: {
  panel: PlayerPanel
  onPanel: (panel: PlayerPanel) => void
}) {
  return (
    <View className="w-full flex-row items-center justify-around">
      <SkipAdButton />
      <PanelButton
        symbol="quote.bubble"
        icon={MessageSquareQuote}
        label="Transcript"
        target="transcript"
        panel={panel}
        onPanel={onPanel}
      />
      <AirPlayButton />
      <PanelButton
        symbol="list.bullet"
        icon={List}
        label="Playing Next"
        target="queue"
        panel={panel}
        onPanel={onPanel}
      />
    </View>
  )
}

/** Skips the ad that plays now: to its end when the phone knows it, else 30 seconds ahead. */
function SkipAdButton() {
  const sheet = useSheet()
  return (
    <Pressable
      className="items-center justify-center rounded-full active:opacity-60"
      style={{
        height: SKIP_AD_BUTTON.height,
        minWidth: SKIP_AD_BUTTON.minWidth,
        paddingHorizontal: SKIP_AD_BUTTON.paddingX,
        backgroundColor: sheet.rest,
      }}
      accessibilityRole="button"
      accessibilityLabel={SKIP_AD_ACCESSIBILITY}
      onPress={() => {
        pick()
        pressSkipAd()
      }}
    >
      <Text
        className="text-sm font-semibold"
        style={{ color: sheet.ink }}
        numberOfLines={1}
        maxFontSizeMultiplier={1.3}
      >
        {SKIP_AD_LABEL}
      </Text>
    </Pressable>
  )
}

function PanelButton({
  symbol,
  icon,
  label,
  target,
  panel,
  onPanel,
}: {
  symbol: SFSymbol
  icon: typeof List
  label: string
  target: PlayerPanel
  panel: PlayerPanel
  onPanel: (panel: PlayerPanel) => void
}) {
  const sheet = useSheet()
  const on = panel === target
  return (
    <Pressable
      className="size-11 items-center justify-center rounded-full active:opacity-60"
      style={on ? { backgroundColor: sheet.rest } : undefined}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ selected: on }}
      onPress={() => {
        pick()
        onPanel(on ? "art" : target)
      }}
    >
      <SFIcon
        name={symbol}
        size={24}
        color={on ? sheet.ink : sheet.tint}
        fallback={icon}
      />
    </Pressable>
  )
}
