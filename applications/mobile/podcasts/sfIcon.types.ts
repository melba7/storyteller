// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { type LucideIcon } from "lucide-react-native"
import { type SFSymbol } from "sf-symbols-typescript"

export type SFIconProps = {
  /** The SF Symbol drawn on iOS. */
  name: SFSymbol
  size: number
  /** A "#rrggbb" colour; the surroundings' text colour when left out. */
  color?: string | undefined
  /** What is drawn where SF Symbols don't exist (Android, the web). */
  fallback: LucideIcon
  /** The fallback is drawn solid (play, pause). */
  filled?: boolean
  /** A number drawn in the middle of the fallback arrow (skip seconds). */
  badge?: number
}
