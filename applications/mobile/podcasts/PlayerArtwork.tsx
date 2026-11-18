// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { View } from "react-native"

import { Artwork } from "./Artwork"

/**
 * The player's artwork, edge to edge: a square as wide as the sheet with square corners, cut
 * off at `height` when the room is shorter than that, its lower part fading into the sheet's
 * colour (`fadeTo`) as the Home card's artwork does. With `contained` (a wide or short sheet),
 * it is a rounded square instead, centred in the box `width` by `height` that starts at `top`,
 * with no fade.
 */
export function PlayerArtwork({
  uri,
  width,
  height,
  fadeTo,
  contained = false,
  top = 0,
}: {
  uri: string | null
  width: number
  height: number
  /** The sheet's "#rrggbb" colour where the artwork ends. */
  fadeTo: string
  contained?: boolean
  /** Where the box starts, for `contained`. */
  top?: number
}) {
  if (contained) {
    const side = Math.floor(Math.min(width, height) - 16)
    if (side <= 0) return null
    return (
      <View
        pointerEvents="none"
        style={{
          position: "absolute",
          top,
          left: 0,
          width,
          height,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Artwork uri={uri} size={side} />
      </View>
    )
  }
  return (
    <View
      pointerEvents="none"
      style={{
        position: "absolute",
        top: 0,
        left: 0,
        width,
        height,
        overflow: "hidden",
      }}
    >
      <Artwork uri={uri} size={width} className="rounded-none border-0" />
      <View
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: height * 0.5 + 1,
          backgroundImage: `linear-gradient(180deg, ${fadeTo}00, ${fadeTo})`,
        }}
      />
    </View>
  )
}
