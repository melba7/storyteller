// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { createContext, useContext } from "react"

import { type SheetColors, sheetColors } from "@/modules/podcasts/playerSheet"

const SheetContext = createContext<SheetColors>(sheetColors(null))

/** Gives the player's parts the sheet's colours, so each picks light or dark ink from them. */
export const SheetProvider = SheetContext.Provider

/** The colours of the player sheet the caller sits on (the dark fallback outside one). */
export function useSheet(): SheetColors {
  return useContext(SheetContext)
}
