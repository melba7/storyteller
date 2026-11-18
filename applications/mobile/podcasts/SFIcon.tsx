// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"

import { type SFIconProps } from "./sfIcon.types"

/** Where SF Symbols don't exist: the matching Lucide icon (the iOS file draws the real symbol). */
export function SFIcon({ size, color, fallback, filled, badge }: SFIconProps) {
  return (
    <View pointerEvents="none" className="items-center justify-center">
      <Icon
        as={fallback}
        size={size}
        {...(color ? { color } : {})}
        {...(filled ? { fill: color ?? "currentColor" } : {})}
      />
      {badge === undefined ? null : (
        <Text
          className="absolute text-xs font-bold"
          style={color ? { color } : undefined}
        >
          {badge}
        </Text>
      )}
    </View>
  )
}
