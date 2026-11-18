// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { List, MessageSquareQuote } from "lucide-react-native"
import { Pressable, View } from "react-native"
import { type SFSymbol } from "sf-symbols-typescript"

import { AirPlayButton } from "./AirPlayButton"
import { type PlayerPanel } from "./PlayerPages"
import { SFIcon } from "./SFIcon"
import { pick } from "./haptics"
import { useSheet } from "./playerSheetContext"

/**
 * The player's bottom row: transcript, AirPlay and the queue spread evenly (at about a sixth, a half and five sixths
 * of the width), the transcript and queue lit while their panel shows. Each panel button toggles its panel in place of the artwork.
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
