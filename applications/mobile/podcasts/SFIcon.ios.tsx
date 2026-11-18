// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Host, Image } from "@expo/ui/swift-ui"
import { View } from "react-native"

import { type SFIconProps } from "./sfIcon.types"

/**
 * A real SF Symbol. It ignores touches, so the Pressable around it keeps them (and VoiceOver
 * reads the Pressable's label, not the symbol).
 */
export function SFIcon({ name, size, color }: SFIconProps) {
  return (
    <View pointerEvents="none">
      <Host matchContents>
        <Image systemName={name} size={size} {...(color ? { color } : {})} />
      </Host>
    </View>
  )
}
