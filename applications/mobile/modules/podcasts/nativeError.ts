// LOFI-FORK: the podcasts section's error messages (see FORK.md).

/**
 * The message to show for a failed call. The Expo module wraps what the Swift side
 * threw ("Call to function ... has been rejected. → Caused by: the message"); the
 * listener should only see the message.
 */
export function readableError(cause: unknown): string {
  const text =
    cause instanceof Error
      ? cause.message
      : typeof cause === "string"
        ? cause
        : String(cause)
  const marker = "Caused by:"
  const at = text.lastIndexOf(marker)
  const message = (at >= 0 ? text.slice(at + marker.length) : text).trim()
  return message === "" ? "Something went wrong." : message
}
