// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { useMemo, useState } from "react"
import { ActivityIndicator, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { saveOwnOrder } from "@/modules/podcasts/db"
import { sortShows } from "@/modules/podcasts/libraryView"
import { readableError } from "@/modules/podcasts/nativeError"

import { Artwork } from "./Artwork"
import { DragList } from "./DragList"
import { ScreenBar } from "./ScreenBar"
import { useShowActivity, useShows } from "./hooks"
import { useLibraryView } from "./useLibraryView"

const ROW_HEIGHT = 64

/**
 * The screen for arranging shows by hand. It starts from the order the library shows now.
 * Drag a row by its handle (or use VoiceOver's Move up and Move down), then Done saves it
 * and switches the library to "Your order". Cancel changes nothing.
 */
export function ArrangeShows() {
  const router = useRouter()
  const shows = useShows()
  const activity = useShowActivity()
  const { view, change } = useLibraryView()
  const [order, setOrder] = useState<string[] | null>(null)
  const [saving, setSaving] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  const byId = useMemo(
    () => new Map((shows.data ?? []).map((show) => [show.id, show])),
    [shows.data],
  )
  // The list is fixed once, from the order on screen; later library changes do not shuffle it.
  const ids =
    order ??
    (shows.data && view
      ? sortShows(shows.data, view.order, activity.data ?? {}).map((s) => s.id)
      : null)

  async function done() {
    if (!ids || saving) return
    setSaving(true)
    setProblem(null)
    try {
      await saveOwnOrder(ids)
      change({ order: "own" })
      router.back()
    } catch (cause) {
      setProblem(readableError(cause))
      setSaving(false)
    }
  }

  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar
        title="Arrange"
        left={
          <Button
            variant="ghost"
            accessibilityLabel="Cancel"
            onPress={() => router.back()}
          >
            <Text className="text-primary">Cancel</Text>
          </Button>
        }
        right={
          <Button
            variant="ghost"
            accessibilityLabel="Done"
            disabled={ids === null || saving}
            onPress={done}
          >
            <Text className="text-primary font-semibold">Done</Text>
          </Button>
        }
      />
      {problem ? (
        <Text className="text-destructive px-4 py-2 text-sm">{problem}</Text>
      ) : null}
      {shows.error && ids === null ? (
        <Text className="text-destructive px-8 py-12 text-center">
          {shows.error}
        </Text>
      ) : ids === null ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : (
        <DragList
          ids={ids}
          rowHeight={ROW_HEIGHT}
          onChange={setOrder}
          label={(id, index, count) =>
            `${byId.get(id)?.title ?? ""}, place ${index + 1} of ${count}`
          }
          renderContent={(id) => {
            const show = byId.get(id)
            if (!show) return null
            return (
              <View className="flex-row items-center gap-3">
                <Artwork uri={show.imageUrl} size={48} />
                <Text className="flex-1 font-semibold" numberOfLines={2}>
                  {show.title}
                </Text>
              </View>
            )
          }}
        />
      )}
    </View>
  )
}
