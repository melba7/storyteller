// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ChevronRight, type LucideIcon } from "lucide-react-native"
import type { ReactNode } from "react"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"

/**
 * The line under a row. It is `border-foreground/10` because in the Dark theme `--color-border`
 * equals the card's colour, so it would not show.
 */
export const ROW = "border-foreground/10 border-b"

/**
 * A titled card of settings rows: a muted title-case header over a rounded card. Give each
 * row `ROW`; the inner `-mb-px` pushes the last row's line out of the card, where it is clipped.
 */
export function SettingsGroup({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <View className="pt-6">
      <Text
        className="text-muted-foreground px-4 pb-2 text-sm font-semibold"
        accessibilityRole="header"
      >
        {title}
      </Text>
      <View className="bg-secondary overflow-hidden rounded-3xl px-4">
        <View className="-mb-px">{children}</View>
      </View>
    </View>
  )
}

/** A row with a title, a line under it and a switch; the switch waits until `checked` is known. */
export function SwitchRow({
  title,
  body,
  checked,
  onChange,
}: {
  title: string
  body: string
  checked: boolean | null
  onChange: (on: boolean) => void
}) {
  return (
    <View className={`${ROW} flex-row items-center gap-3 py-3`}>
      <View className="flex-1">
        <Text className="font-semibold">{title}</Text>
        <Text className="text-muted-foreground text-sm">{body}</Text>
      </View>
      {checked === null ? null : (
        <Switch
          accessibilityLabel={title}
          checked={checked}
          onCheckedChange={onChange}
        />
      )}
    </View>
  )
}

/** A row that opens another screen: an icon, a title, a line under it and a chevron. */
export function LinkRow({
  icon,
  title,
  body,
  label,
  onPress,
}: {
  icon: LucideIcon
  title: string
  body: string
  label: string
  onPress: () => void
}) {
  return (
    <Pressable
      className={`${ROW} active:bg-foreground/5 flex-row items-center gap-3 py-3`}
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Icon as={icon} size={22} className="text-primary" />
      <View className="flex-1">
        <Text className="font-semibold">{title}</Text>
        <Text className="text-muted-foreground text-sm">{body}</Text>
      </View>
      <Icon as={ChevronRight} size={20} className="text-muted-foreground" />
    </Pressable>
  )
}
