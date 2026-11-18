// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pause } from "lucide-react-native"
import { ActivityIndicator } from "react-native"

import { Text } from "@/components/ui/text"

import { PressableScale } from "./PressableScale"

/**
 * The white capsule on a show's or an episode's coloured header: a play (or pause) glyph and
 * a bold label, both in the header's own colour. It is at least 48 pt high and grows with
 * large text. `status` is what the episode behind it is doing.
 */
export function HeaderCapsule({
  label,
  accessibilityLabel,
  status,
  color,
  disabled = false,
  onPress,
}: {
  label: string
  accessibilityLabel: string
  status: "idle" | "playing" | "buffering"
  /** The header's colour, for the glyph and the label. */
  color: string
  disabled?: boolean
  onPress: () => void
}) {
  return (
    <PressableScale
      style={{
        minHeight: 48,
        flexDirection: "row",
        alignItems: "center",
        justifyContent: "center",
        gap: 8,
        borderRadius: 999,
        paddingHorizontal: 32,
        paddingVertical: 8,
        backgroundColor: "#ffffff",
        opacity: disabled ? 0.6 : 1,
      }}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      disabled={disabled}
      onPress={onPress}
    >
      {status === "buffering" ? (
        <ActivityIndicator color={color} />
      ) : status === "playing" ? (
        <Pause size={20} color={color} fill={color} />
      ) : (
        <Text style={{ color, fontSize: 20, lineHeight: 24 }}>{"▶︎"}</Text>
      )}
      <Text
        style={{ color, fontSize: 19, fontWeight: "700", flexShrink: 1 }}
        numberOfLines={1}
      >
        {label}
      </Text>
    </PressableScale>
  )
}
