// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { View, useWindowDimensions } from "react-native"

import {
  SHELF_GAP,
  SHELF_GUTTER,
  SHELF_LINE_HEIGHT,
  SHELF_TEXT_GAP,
  shelfHeight,
  shelfTileSize,
} from "@/modules/podcasts/homeLook"

/**
 * A loading shelf: three grey rounded squares with two grey bars under each, exactly as tall
 * as a real `ShowShelf` (`ranked` adds the rank line), so the page does not jump when the
 * shows arrive. It is hidden from VoiceOver.
 */
export function ShelfSkeleton({ ranked = false }: { ranked?: boolean }) {
  const { width: window } = useWindowDimensions()
  const size = shelfTileSize(window)
  const textLines = ranked ? 3 : 2
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      style={{
        height: shelfHeight(size, ranked),
        flexDirection: "row",
        overflow: "hidden",
        paddingHorizontal: SHELF_GUTTER,
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
              height: textLines * SHELF_LINE_HEIGHT,
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
