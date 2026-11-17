// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { type LucideIcon } from "lucide-react-native"
import { type SFSymbol } from "sf-symbols-typescript"

export type SFIconProps = {
  /** The SF Symbol drawn on iOS. */
  name: SFSymbol
  size: number
  /**
   * A "#rrggbb" colour. Left out, iOS draws the symbol in its own label colour, not the
   * section's text colour, so pass the theme's colour wherever the Appearance can differ.
   */
  color?: string | undefined
  /** What is drawn where SF Symbols don't exist (Android, the web). */
  fallback: LucideIcon
  /** The fallback is drawn solid (play, pause). */
  filled?: boolean
  /** A number drawn in the middle of the fallback arrow (skip seconds). */
  badge?: number
}
