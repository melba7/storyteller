// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ChevronRight, type LucideIcon } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"

/**
 * One row of the Library list: a purple icon, the name in large type, an optional grey count
 * and a chevron. The separator under it starts at the text and stops at the chevron's right edge.
 */
export function LibraryRow({
  icon,
  title,
  count,
  label,
  onPress,
}: {
  icon: LucideIcon
  title: string
  /** Shown in grey before the chevron; nothing when it is null. */
  count?: number | string | null | undefined
  /** For VoiceOver; the title and the count when it is left out. */
  label?: string
  onPress: () => void
}) {
  const shown = count === null || count === undefined ? "" : String(count)
  return (
    <Pressable
      className="active:bg-foreground/5 flex-row items-center px-4"
      accessibilityRole="button"
      accessibilityLabel={label ?? (shown ? `${title}, ${shown}` : title)}
      onPress={onPress}
    >
      <View className="w-12 items-start">
        <Icon as={icon} size={26} className="text-primary" />
      </View>
      <View className="border-foreground/15 min-h-14 flex-1 flex-row items-center gap-2 border-b py-3">
        <Text className="flex-1 text-xl" numberOfLines={1}>
          {title}
        </Text>
        {shown ? (
          <Text className="text-muted-foreground text-xl">{shown}</Text>
        ) : null}
        <Icon as={ChevronRight} size={20} className="text-muted-foreground" />
      </View>
    </Pressable>
  )
}
