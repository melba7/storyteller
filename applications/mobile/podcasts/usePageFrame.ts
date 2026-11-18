// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useWindowDimensions } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { type PageFrame, pageFrame } from "@/modules/podcasts/pageFrame"

/**
 * The frame a page's shelves and grids are laid out in: each side's padding (at least 16 pt,
 * or its safe-area inset) and the width to size tiles from. It reads the measured window and
 * insets on every render, so a fold, an unfold or a turn re-lays the page out in place, with
 * nothing remounted.
 */
export function usePageFrame(): PageFrame {
  const { width } = useWindowDimensions()
  const insets = useSafeAreaInsets()
  return pageFrame(width, insets)
}
