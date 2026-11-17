// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useEffect } from "react"
import Animated, {
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withSpring,
} from "react-native-reanimated"

import { Artwork } from "./Artwork"

const PAUSED_SCALE = 0.88

/** The large artwork: rounded, with a soft shadow, springing a little smaller while paused. */
export function PlayerArtwork({
  uri,
  size,
  playing,
}: {
  uri: string | null
  size: number
  playing: boolean
}) {
  const reduceMotion = useReducedMotion()
  const scale = useSharedValue(playing ? 1 : PAUSED_SCALE)
  useEffect(() => {
    const target = playing ? 1 : PAUSED_SCALE
    scale.set(reduceMotion ? target : withSpring(target))
  }, [playing, reduceMotion, scale])
  const style = useAnimatedStyle(() => ({
    transform: [{ scale: scale.get() }],
  }))
  return (
    <Animated.View
      style={[
        {
          width: size,
          height: size,
          borderRadius: 12,
          boxShadow: "0 18px 40px rgba(0,0,0,0.35)",
        },
        style,
      ]}
    >
      <Artwork uri={uri} size={size} className="rounded-xl border-0" />
    </Animated.View>
  )
}
