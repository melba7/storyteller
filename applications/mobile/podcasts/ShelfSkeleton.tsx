// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { PixelRatio, View } from "react-native"

import {
  SHELF_GAP,
  SHELF_LINE_HEIGHT,
  SHELF_TEXT_GAP,
  shelfHeight,
  shelfTextScale,
  shelfTileSize,
} from "@/modules/podcasts/homeLook"

import { usePageFrame } from "./usePageFrame"

/**
 * A loading shelf: three grey rounded squares with two grey bars under each, exactly as tall
 * as a real `ShowShelf` (`ranked` adds the rank line), so the page does not jump when the
 * shows arrive. It is hidden from VoiceOver.
 */
export function ShelfSkeleton({ ranked = false }: { ranked?: boolean }) {
  const frame = usePageFrame()
  const size = shelfTileSize(frame.width)
  const textLines = ranked ? 3 : 2
  const scale = shelfTextScale(PixelRatio.getFontScale())
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      style={{
        height: shelfHeight(size, ranked, scale),
        flexDirection: "row",
        overflow: "hidden",
        paddingLeft: frame.left,
        paddingRight: frame.right,
        gap: SHELF_GAP,
      }}
    >
      {[0, 1, 2].map((index) => (
        <View key={index} style={{ width: size }}>
          <View
            className="bg-secondary rounded-[10px]"
            style={{ height: size }}
          />
          <View
            style={{
              marginTop: SHELF_TEXT_GAP,
              height: textLines * Math.ceil(SHELF_LINE_HEIGHT * scale),
              justifyContent: "flex-end",
              gap: 8,
            }}
          >
            <View className="bg-secondary h-4 w-4/5 rounded-full" />
            <View className="bg-secondary h-4 w-3/5 rounded-full" />
          </View>
        </View>
      ))}
    </View>
  )
}
