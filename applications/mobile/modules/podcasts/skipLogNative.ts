// LOFI-FORK: the podcasts section's skip log (see FORK.md).
//
// The real ways for `sendSkipLog`: the native copy of the log, and the share sheet that the OPML
// export uses. Not imported by any test, because both are native.
import * as Sharing from "expo-sharing"

import { Podcasts } from "./index"
import { sendSkipLog } from "./skipLog"

/** Opens the share sheet with the skip log. "empty" when no skip is logged yet. */
export function shareSkipLog(): Promise<"shared" | "empty"> {
  return sendSkipLog({
    copyLog: async () => (await Podcasts?.exportSkipLog()) ?? null,
    canShare: () => Sharing.isAvailableAsync(),
    share: (address) =>
      Sharing.shareAsync(address, { dialogTitle: "Send skip log" }),
  })
}
