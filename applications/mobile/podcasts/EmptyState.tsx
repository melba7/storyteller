// LOFI-FORK: the podcasts section's screens (see FORK.md).
import type { LucideIcon } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"

/**
 * What an empty screen shows: an icon in a soft circle, a short title, a line on what to do,
 * and, when there is a next step, one button for it.
 */
export function EmptyState({
  icon,
  title,
  body,
  action,
}: {
  icon: LucideIcon
  title: string
  body?: string
  action?: { label: string; onPress: () => void }
}) {
  return (
    <View className="items-center gap-3 px-8 py-12">
      <View className="bg-primary/15 size-16 items-center justify-center rounded-full">
        <Icon as={icon} size={30} className="text-primary" />
      </View>
      <Text
        className="text-center text-xl font-bold"
        accessibilityRole="header"
      >
        {title}
      </Text>
      {body ? (
        <Text className="text-muted-foreground text-center text-base">
          {body}
        </Text>
      ) : null}
      {action ? (
        <Pressable
          className="bg-primary mt-2 min-h-11 items-center justify-center rounded-full px-6 active:opacity-80"
          accessibilityRole="button"
          onPress={action.onPress}
        >
          <Text className="text-primary-foreground font-semibold">
            {action.label}
          </Text>
        </Pressable>
      ) : null}
    </View>
  )
}
