// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Share2 } from "lucide-react-native"
import { Alert, Pressable, Share } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { readableError } from "@/modules/podcasts/nativeError"
import type { ShareMessage } from "@/modules/podcasts/share"

async function open(build: () => ShareMessage | null) {
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
 * playing now changes). `label` is what VoiceOver says. The `player` look is the round
 * button on the dark player; the page look is an outlined button.
 */
export function ShareButton({
  build,
  label,
  look = "page",
}: {
  build: () => ShareMessage | null
  label: string
  look?: "page" | "player"
}) {
  if (look === "player") {
    return (
      <Pressable
        className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
        accessibilityRole="button"
        accessibilityLabel={label}
        onPress={() => void open(build)}
      >
        <Icon as={Share2} size={20} className="text-white" />
      </Pressable>
    )
  }
  return (
    <Button
      variant="outline"
      className="rounded-full"
      accessibilityLabel={label}
      onPress={() => void open(build)}
    >
      <Icon as={Share2} size={18} className="text-primary" />
      <Text>Share</Text>
    </Button>
  )
}
