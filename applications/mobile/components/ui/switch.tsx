import { Host as BaseHost, Switch as ExpoSwitch } from "@expo/ui"
import { Switch as BaseComposeSwitch } from "@expo/ui/jetpack-compose"
import { testID as composeTestID } from "@expo/ui/jetpack-compose/modifiers"
import {
  accessibilityLabel as swiftAccessibilityLabel,
  tint,
} from "@expo/ui/swift-ui/modifiers"
import { type ComponentProps } from "react"
import { type ColorValue, Platform, View } from "react-native"
import { withUniwind } from "uniwind"

import { cn } from "@/lib/utils"

type IOSSwitchProps = ComponentProps<typeof ExpoSwitch> & {
  accessibilityLabel?: string | undefined
  tintColor?: ColorValue | undefined
}

type AndroidSwitchProps = ComponentProps<typeof BaseComposeSwitch> & {
  checkedBorderColor?: ColorValue | undefined
  checkedThumbColor?: ColorValue | undefined
  checkedTrackColor?: ColorValue | undefined
  uncheckedBorderColor?: ColorValue | undefined
  uncheckedThumbColor?: ColorValue | undefined
  uncheckedTrackColor?: ColorValue | undefined
}

type Props = {
  accessibilityLabel?: string | undefined
  checked: boolean
  className?: string | undefined
  disabled?: boolean | undefined
  onCheckedChange: (checked: boolean) => void
  testID?: string | undefined
}

const Host = withUniwind(BaseHost)

function BaseIOSSwitch({
  accessibilityLabel,
  modifiers,
  tintColor,
  ...props
}: IOSSwitchProps) {
  const switchModifiers = [
    ...(tintColor ? [tint(tintColor)] : []),
    ...(accessibilityLabel
      ? [swiftAccessibilityLabel(accessibilityLabel)]
      : []),
    ...(modifiers ?? []),
  ]

  return (
    <ExpoSwitch
      {...props}
      {...(switchModifiers.length ? { modifiers: switchModifiers } : {})}
    />
  )
}

const IOSSwitch = withUniwind(BaseIOSSwitch, {
  tintColor: {
    fromClassName: "tintColorClassName",
    styleProperty: "color",
  },
})

function BaseAndroidSwitch({
  checkedBorderColor,
  checkedThumbColor,
  checkedTrackColor,
  uncheckedBorderColor,
  uncheckedThumbColor,
  uncheckedTrackColor,
  colors,
  ...props
}: AndroidSwitchProps) {
  const switchColors = {
    ...colors,
    ...(checkedBorderColor ? { checkedBorderColor } : {}),
    ...(checkedThumbColor ? { checkedThumbColor } : {}),
    ...(checkedTrackColor ? { checkedTrackColor } : {}),
    ...(uncheckedBorderColor ? { uncheckedBorderColor } : {}),
    ...(uncheckedThumbColor ? { uncheckedThumbColor } : {}),
    ...(uncheckedTrackColor ? { uncheckedTrackColor } : {}),
  }

  return (
    <BaseComposeSwitch
      {...props}
      {...(Object.keys(switchColors).length ? { colors: switchColors } : {})}
    />
  )
}

const AndroidSwitch = withUniwind(BaseAndroidSwitch, {
  checkedBorderColor: {
    fromClassName: "checkedBorderColorClassName",
    styleProperty: "borderColor",
  },
  checkedThumbColor: {
    fromClassName: "checkedThumbColorClassName",
    styleProperty: "color",
  },
  checkedTrackColor: {
    fromClassName: "checkedTrackColorClassName",
    styleProperty: "backgroundColor",
  },
  uncheckedBorderColor: {
    fromClassName: "uncheckedBorderColorClassName",
    styleProperty: "borderColor",
  },
  uncheckedThumbColor: {
    fromClassName: "uncheckedThumbColorClassName",
    styleProperty: "color",
  },
  uncheckedTrackColor: {
    fromClassName: "uncheckedTrackColorClassName",
    styleProperty: "backgroundColor",
  },
})

export function Switch({
  accessibilityLabel,
  checked,
  className,
  disabled,
  onCheckedChange,
  testID,
}: Props) {
  const androidSwitchModifiers =
    Platform.OS === "android" && testID ? [composeTestID(testID)] : []

  return (
    <View
      accessibilityLabel={accessibilityLabel}
      accessibilityRole="switch"
      accessibilityState={{ checked, disabled: disabled ?? false }}
      className={cn(
        "shrink-0",
        disabled ? "opacity-50" : "opacity-100",
        className,
      )}
    >
      <Host matchContents className="self-center">
        {Platform.OS === "android" ? (
          <AndroidSwitch
            value={checked}
            onCheckedChange={onCheckedChange}
            enabled={!disabled}
            checkedBorderColorClassName="border-primary"
            checkedThumbColorClassName="text-primary-foreground"
            checkedTrackColorClassName="bg-primary"
            uncheckedBorderColorClassName="border-input"
            uncheckedThumbColorClassName="text-primary-foreground"
            uncheckedTrackColorClassName="bg-input"
            modifiers={androidSwitchModifiers}
          />
        ) : (
          <IOSSwitch
            value={checked}
            onValueChange={onCheckedChange}
            disabled={disabled ?? false}
            accessibilityLabel={accessibilityLabel}
            tintColorClassName="text-primary"
            {...(testID ? { testID } : {})}
          />
        )}
      </Host>
    </View>
  )
}
