// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { type ComponentProps, type ReactNode } from "react"
import { Pressable, type StyleProp, type ViewStyle } from "react-native"
import Animated, {
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withSpring,
} from "react-native-reanimated"

const PRESSED_SCALE = 0.96

/**
 * A pressable that springs a little smaller while pressed, for artwork tiles and cards. With
 * Reduce Motion on it dims instead.
 */
export function PressableScale({
  children,
  style,
  onPressIn,
  onPressOut,
  ...props
}: Omit<ComponentProps<typeof Pressable>, "style" | "children"> & {
  style?: StyleProp<ViewStyle>
  children?: ReactNode
}) {
  const reduceMotion = useReducedMotion()
  const pressed = useSharedValue(0)
  const look = useAnimatedStyle(() =>
    reduceMotion
      ? { opacity: pressed.get() === 1 ? 0.7 : 1 }
      : {
          transform: [
            { scale: withSpring(pressed.get() === 1 ? PRESSED_SCALE : 1) },
          ],
        },
  )
  return (
    <Pressable
      {...props}
      onPressIn={(event) => {
        pressed.set(1)
        onPressIn?.(event)
      }}
      onPressOut={(event) => {
        pressed.set(0)
        onPressOut?.(event)
      }}
    >
      <Animated.View style={[style, look]}>{children}</Animated.View>
    </Pressable>
  )
}
