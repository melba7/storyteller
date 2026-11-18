// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useState } from "react"
import { Alert, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { readableError } from "@/modules/podcasts/nativeError"
import { shareSkipLog } from "@/modules/podcasts/skipLogNative"

import { ROW } from "./SettingsGroup"

/**
 * Profile's "Send skip log" row. Swift notes each ad skip on the phone (the last 500) with how
 * it ended and the words around its edges; the file is only sent when this button is tapped.
 */
export function SkipLogRow() {
  const [busy, setBusy] = useState(false)

  async function send() {
    setBusy(true)
    try {
      if ((await shareSkipLog()) === "empty") {
        Alert.alert("Nothing to send", "No ad has been skipped yet.")
      }
    } catch (cause) {
      Alert.alert("Couldn't send the skip log", readableError(cause))
    } finally {
      setBusy(false)
    }
  }

  return (
    <View className={`${ROW} gap-2 py-3`}>
      <Text className="font-semibold">Skip log</Text>
      <Text className="text-muted-foreground text-sm">
        The phone notes each ad it skips, how it ended and the words around its
        start and end. The last 500 are kept here, and nothing leaves your phone
        unless you send it.
      </Text>
      <Button
        variant="outline"
        className="rounded-full"
        disabled={busy}
        accessibilityLabel="Send the skip log"
        onPress={() => void send()}
      >
        <Text>Send skip log</Text>
      </Button>
    </View>
  )
}
