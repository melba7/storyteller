// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"
import { Alert, View } from "react-native"

import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import {
  loadNotifyNew,
  notificationPermission,
  requestNotificationPermission,
  saveNotifyNew,
} from "@/modules/podcasts/notificationsNative"

/** Profile's "Notify me about new episodes" switch. It asks iOS for permission when turned on. */
export function NotifyRow() {
  const [on, setOn] = useState<boolean | null>(null)

  useEffect(() => {
    let live = true
    // On only while iOS still allows notifications: the listener may have turned them off.
    Promise.all([loadNotifyNew(), notificationPermission()]).then(
      ([saved, permission]) => {
        if (live) setOn(saved && permission === "granted")
      },
      () => {
        if (live) setOn(false)
      },
    )
    return () => {
      live = false
    }
  }, [])

  async function change(wanted: boolean) {
    const before = on
    setOn(wanted)
    try {
      if (wanted && !(await requestNotificationPermission())) {
        setOn(before)
        Alert.alert(
          "Notifications are off",
          "To hear about new episodes, allow notifications for this app in the iOS Settings.",
        )
        return
      }
      await saveNotifyNew(wanted)
    } catch {
      setOn(before)
      Alert.alert("Couldn't save the setting", "Try again in a moment.")
    }
  }

  return (
    <View className="border-border flex-row items-center gap-3 border-b py-3">
      <View className="flex-1">
        <Text className="font-semibold">Notify me about new episodes</Text>
        <Text className="text-muted-foreground text-sm">
          One notification for each show, when it has something new.
        </Text>
      </View>
      {on === null ? null : (
        <Switch
          accessibilityLabel="Notify me about new episodes"
          checked={on}
          onCheckedChange={(value) => void change(value)}
        />
      )}
    </View>
  )
}
