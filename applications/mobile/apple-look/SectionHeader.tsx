// LOFI-FORK: the Apple Podcasts look for the Books side (see FORK.md).
import { ChevronRight } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { cn } from "@/lib/utils"

interface Props {
  title: string
  /** Opens the list behind the heading. Without it the heading is plain, with no chevron. */
  onPress?: () => void
  /** What VoiceOver reads for the pressable heading. */
  accessibilityLabel?: string
  className?: string
}

/**
 * Apple's section heading: the title in 22 bold. With `onPress` a muted chevron follows it
 * and the whole heading is a button.
 */
export function SectionHeader({
  title,
  onPress,
  accessibilityLabel,
  className,
}: Props) {
  const content = (
    <>
      <Text variant="h2" className="shrink">
        {title}
      </Text>
      {onPress ? (
        <Icon
          as={ChevronRight}
          size={20}
          strokeWidth={2.5}
          className="text-muted-foreground mt-0.5"
        />
      ) : null}
    </>
  )

  if (!onPress) {
    return (
      <View className={cn("flex-row items-center gap-1", className)}>
        {content}
      </View>
    )
  }

  return (
    <Pressable
      accessibilityLabel={accessibilityLabel}
      accessibilityRole="button"
      onPress={onPress}
      className={cn("flex-row items-center gap-1 active:opacity-70", className)}
    >
      {content}
    </Pressable>
  )
}
