// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ChevronRight } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"

/**
 * A section's bold title. With `onPress` it carries a grey chevron and opens the section's
 * page; without, it is a plain heading.
 */
export function SectionHeader({
  title,
  onPress,
}: {
  title: string
  onPress?: () => void
}) {
  const label = <Text className="text-[28px] leading-8 font-bold">{title}</Text>
  if (!onPress) {
    return (
      <View
        className="flex-row items-center gap-1 px-4 pt-7 pb-3"
        accessibilityRole="header"
      >
        {label}
      </View>
    )
  }
  return (
    <Pressable
      className="flex-row items-center gap-1 px-4 pt-7 pb-3"
      accessibilityRole="header"
      accessibilityLabel={title}
      onPress={onPress}
    >
      {label}
      <Icon as={ChevronRight} size={24} className="text-muted-foreground" />
    </Pressable>
  )
}
