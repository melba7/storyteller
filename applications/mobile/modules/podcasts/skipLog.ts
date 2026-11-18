// LOFI-FORK: the podcasts section's skip log (see FORK.md).
//
// Swift keeps the log (one line for each ad skip, with the words around its edges) on the phone.
// Nothing is sent by itself: this is the one way out, the share sheet, when the listener taps
// "Send skip log". The ways to copy the file and to share it are given in, so this can be
// tested; `skipLogNative.ts` gives the real ones.

export type SkipLogWays = {
  /** Makes a copy the share sheet can read and gives its address, or null when nothing is logged. */
  copyLog: () => Promise<string | null>
  canShare: () => Promise<boolean>
  share: (address: string) => Promise<void>
}

/** "empty" when no skip is logged yet, "shared" once the share sheet was opened. */
export async function sendSkipLog(
  ways: SkipLogWays,
): Promise<"shared" | "empty"> {
  const address = await ways.copyLog()
  if (!address) return "empty"
  if (!(await ways.canShare())) {
    throw new Error("Sharing isn't available on this device.")
  }
  await ways.share(address)
  return "shared"
}
