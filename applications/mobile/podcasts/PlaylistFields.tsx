// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Check } from "lucide-react-native"
import { type ReactNode } from "react"
import { Pressable, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import { type Show } from "@/modules/podcasts/library"

export function Row({
  title,
  body,
  children,
}: {
  title: string
  body?: string
  children: ReactNode
}) {
  return (
    <View className="border-border flex-row items-center gap-3 border-b py-3">
      <View className="flex-1">
        <Text className="font-semibold">{title}</Text>
        {body ? (
          <Text className="text-muted-foreground text-sm">{body}</Text>
        ) : null}
      </View>
      {children}
    </View>
  )
}

export function Heading({ children }: { children: string }) {
  return (
    <Text className="text-muted-foreground px-1 pt-6 pb-1 text-xs uppercase">
      {children}
    </Text>
  )
}

export function SwitchRow(props: {
  title: string
  body?: string
  checked: boolean
  onChange: (on: boolean) => void
}) {
  return (
    <Row title={props.title} {...(props.body ? { body: props.body } : {})}>
      <Switch
        accessibilityLabel={props.title}
        checked={props.checked}
        onCheckedChange={props.onChange}
      />
    </Row>
  )
}

/** A row whose value is picked from a menu. */
export function ChoiceRow<T extends string>({
  title,
  value,
  choices,
  onChange,
}: {
  title: string
  value: T
  choices: readonly { id: T; title: string }[]
  onChange: (value: T) => void
}) {
  const current = choices.find((choice) => choice.id === value)?.title ?? ""
  return (
    <Row title={title}>
      <Menu
        actions={choices.map((choice) => ({
          id: choice.id,
          title: choice.title,
          state: choice.id === value ? ("on" as const) : ("off" as const),
          onPress: () => onChange(choice.id),
        }))}
      >
        <Button
          variant="outline"
          size="sm"
          accessibilityLabel={`${title}: ${current}`}
        >
          <Text>{current}</Text>
        </Button>
      </Menu>
    </Row>
  )
}

/** Rows to tick several of a list (the shows, the played states). */
export function PickRows({
  options,
  picked,
  onToggle,
}: {
  options: readonly { id: string; title: string }[]
  picked: readonly string[]
  onToggle: (id: string) => void
}) {
  return (
    <View>
      {options.map((option) => {
        const on = picked.includes(option.id)
        return (
          <Pressable
            key={option.id}
            className="border-border active:bg-secondary min-h-11 flex-row items-center gap-3 border-b py-2"
            accessibilityRole="checkbox"
            accessibilityState={{ checked: on }}
            accessibilityLabel={option.title}
            onPress={() => onToggle(option.id)}
          >
            <Text className="flex-1">{option.title}</Text>
            {on ? <Icon as={Check} size={20} className="text-primary" /> : null}
          </Pressable>
        )
      })}
    </View>
  )
}

export function showOptions(shows: readonly Show[]) {
  return shows.map((show) => ({ id: show.id, title: show.title }))
}
