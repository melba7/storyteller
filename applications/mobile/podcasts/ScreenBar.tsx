// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { type ReactNode } from "react"
import { View } from "react-native"

import { BackButton } from "@/components/BackButton"
import { Text } from "@/components/ui/text"

interface Props {
  title: string
  /** Replaces the back button (the section menu button on the Podcasts screen). */
  left?: ReactNode
  right?: ReactNode
}

/** The top bar of a podcasts screen: back button, title, and whatever goes on the right. */
export function ScreenBar({ title, left, right }: Props) {
  return (
    <View className="px-safe-or-2 w-full flex-row items-center gap-2">
      {left ?? <BackButton fallback="/podcasts" />}
      <Text
        variant="h3"
        className="font-youngserif my-2 flex-1"
        numberOfLines={1}
      >
        {title}
      </Text>
      {right}
    </View>
  )
}
