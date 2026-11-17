// LOFI-FORK: the Apple Podcasts look for the Books side (see FORK.md).
import { GlassView, isLiquidGlassAvailable } from "expo-glass-effect"
import { type ReactNode } from "react"
import { View, type ViewStyle } from "react-native"
import { withUniwind } from "uniwind"

import { cn } from "@/lib/utils"

// GlassView is not a React Native core view, so it needs Uniwind's wrapper to take classes.
const StyledGlassView = withUniwind(GlassView)

type Props = {
  children: ReactNode
  /** Classes for the capsule itself, for example its height or padding. */
  className?: string | undefined
  /** Classes for the soft shadow wrapper, for example its position. */
  wrapperClassName?: string | undefined
  style?: ViewStyle | undefined
}

/**
 * A rounded capsule with a soft shadow. On iOS 26 it is Liquid Glass; where
 * glass is not available (older iOS, Android) it is a plain `bg-secondary` view.
 * The caller lays out the children.
 */
export function GlassCapsule({
  children,
  className,
  wrapperClassName,
  style,
}: Props) {
  const glass = isLiquidGlassAvailable()

  return (
    <View
      className={cn("rounded-full shadow-lg shadow-black/20", wrapperClassName)}
    >
      {glass ? (
        <StyledGlassView
          glassEffectStyle="regular"
          className={cn("overflow-hidden rounded-full", className)}
          style={style}
        >
          {children}
        </StyledGlassView>
      ) : (
        <View
          className={cn("bg-secondary overflow-hidden rounded-full", className)}
          style={style}
        >
          {children}
        </View>
      )}
    </View>
  )
}
