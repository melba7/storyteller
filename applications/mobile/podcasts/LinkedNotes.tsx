// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Linking } from "react-native"

import { Text } from "@/components/ui/text"
import { splitNotes } from "@/modules/podcasts/episodeLook"

function open(url: string) {
  // A link the phone can't open is ignored; there is nothing useful to tell the listener.
  Linking.openURL(url).catch(() => {})
}

/** An episode's notes as selectable text, with each http(s) link pressable. */
export function LinkedNotes({ notes }: { notes: string }) {
  return (
    <Text selectable className="text-base leading-6">
      {splitNotes(notes).map((part, index) =>
        part.type === "link" ? (
          <Text
            key={index}
            className="text-primary text-base leading-6 underline"
            accessibilityRole="link"
            onPress={() => open(part.url)}
          >
            {part.text}
          </Text>
        ) : (
          part.text
        ),
      )}
    </Text>
  )
}
