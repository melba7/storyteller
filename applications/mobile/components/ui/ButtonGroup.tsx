import {
  type ReactElement,
  cloneElement,
  createContext,
  useContext,
  useMemo,
} from "react"
import { Pressable, View } from "react-native"

import { cn } from "@/lib/utils"

import { type ButtonProps } from "./button"
import { TextClassContext } from "./text"

type ButtonGroupContextValue = {
  onPress: (value: unknown) => void
  currentValue: unknown
}

const ButtonGroupContext = createContext(
  null as unknown as ButtonGroupContextValue,
)

type Props<Value> = {
  children: ReactElement<{
    value: Value
    neighbors?: "left" | "right" | "both"
  }>[]
  onChange: (value: Value) => void
  value: Value
}

export function ButtonGroup<Value>({
  value,
  onChange,
  children,
}: Props<Value>) {
  const contextValue = useMemo(
    () =>
      ({
        currentValue: value,
        onPress: onChange as (value: unknown) => void,
      }) satisfies ButtonGroupContextValue,
    [onChange, value],
  )

  return (
    <ButtonGroupContext.Provider value={contextValue}>
      <View className="bg-accent flex-row self-start rounded-full p-0.5">
        {children.map((child, i) => {
          if (children.length === 1) return child
          if (i === 0 && children.length > 1) {
            return cloneElement(child, {
              key: String(child.props.value),
              neighbors: "right",
            })
          }
          if (i === children.length - 1) {
            return cloneElement(child, {
              key: String(child.props.value),
              neighbors: "left",
            })
          }
          return cloneElement(child, {
            key: String(child.props.value),
            neighbors: "both",
          })
        })}
      </View>
    </ButtonGroupContext.Provider>
  )
}

export function ButtonGroupButton<Value>({
  value,
  // The neighbours are no longer needed: segments are all capsules in a track.
  neighbors: _neighbors,
  variant: _variant,
  size,
  className,
  ...props
}: ButtonProps & { value: Value; neighbors?: "left" | "right" | "both" }) {
  const { onPress, currentValue } = useContext(ButtonGroupContext)
  const selected = currentValue === value
  return (
    <TextClassContext.Provider
      value={cn(
        "text-[13px] font-medium",
        selected ? "text-foreground" : "text-foreground/80",
      )}
    >
      <Pressable
        accessibilityRole="button"
        role="button"
        {...props}
        accessibilityState={{
          ...props.accessibilityState,
          selected,
        }}
        className={cn(
          "min-h-8 items-center justify-center rounded-full px-3",
          size === "sm" && "min-h-7 px-2.5",
          selected && "bg-background dark:bg-ring shadow-sm shadow-black/15",
          props.disabled && "opacity-50",
          className,
        )}
        onPress={() => onPress(value)}
      />
    </TextClassContext.Provider>
  )
}
