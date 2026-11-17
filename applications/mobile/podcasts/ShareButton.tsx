// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Share2 } from "lucide-react-native"
import { Alert, Share } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { readableError } from "@/modules/podcasts/nativeError"
import type { ShareMessage } from "@/modules/podcasts/share"

/** Opens the share sheet with what `build` says (also used by the player's "…" menu). */
export async function shareContent(build: () => ShareMessage | null) {
  const content = build()
  if (!content) {
    Alert.alert("Nothing to share", "This episode has no web address.")
    return
  }
  try {
    await Share.share({ title: content.title, message: content.message })
  } catch (cause) {
    Alert.alert("Couldn't share", readableError(cause))
  }
}

/**
 * Opens the share sheet with what `build` says, made when the button is pressed (the place
 * playing now changes). `label` is what VoiceOver says.
 */
export function ShareButton({
  build,
  label,
}: {
  build: () => ShareMessage | null
  label: string
}) {
  return (
    <Button
      variant="outline"
      className="rounded-full"
      accessibilityLabel={label}
      onPress={() => void shareContent(build)}
    >
      <Icon as={Share2} size={18} className="text-primary" />
      <Text>Share</Text>
    </Button>
  )
}
