// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { GripVertical } from "lucide-react-native"
import { useMemo, useRef, useState } from "react"
import { ActivityIndicator, ScrollView, View } from "react-native"
import { Gesture, GestureDetector } from "react-native-gesture-handler"
import Animated, {
  type SharedValue,
  useAnimatedStyle,
  useSharedValue,
} from "react-native-reanimated"
import { scheduleOnRN } from "react-native-worklets"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { dropIndex, moveShow } from "@/modules/podcasts/arrange"
import { saveOwnOrder } from "@/modules/podcasts/db"
import { type Show } from "@/modules/podcasts/library"
import { sortShows } from "@/modules/podcasts/libraryView"
import { readableError } from "@/modules/podcasts/nativeError"

import { Artwork } from "./Artwork"
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
      {ids === null ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : (
        <ArrangeList
          ids={ids}
          byId={byId}
          onChange={(next) => setOrder(next)}
        />
      )}
    </View>
  )
}

function ArrangeList({
  ids,
  byId,
  onChange,
}: {
  ids: string[]
  byId: Map<string, Show>
  onChange: (ids: string[]) => void
}) {
  // The row being dragged, where it started, and how far the finger has moved.
  const [dragging, setDragging] = useState<string | null>(null)
  const start = useRef(0)
  const translation = useSharedValue(0)
  const latest = useRef(ids)
  latest.current = ids

  function begin(id: string) {
    start.current = latest.current.indexOf(id)
    setDragging(id)
  }

  function over(id: string, distance: number) {
    const from = latest.current.indexOf(id)
    const to = dropIndex(
      start.current,
      distance,
      ROW_HEIGHT,
      latest.current.length,
    )
    if (from !== to) onChange(moveShow(latest.current, from, to))
  }

  function end() {
    setDragging(null)
    translation.set(0)
  }

  function step(id: string, by: number) {
    const from = latest.current.indexOf(id)
    onChange(moveShow(latest.current, from, from + by))
  }

  return (
    <ScrollView
      scrollEnabled={dragging === null}
      contentContainerClassName="px-safe-or-4"
      contentInsetAdjustmentBehavior="automatic"
    >
      {ids.map((id, index) => {
        const show = byId.get(id)
        if (!show) return null
        return (
          <ArrangeRow
            key={id}
            show={show}
            index={index}
            count={ids.length}
            dragging={dragging === id}
            shift={(index - start.current) * ROW_HEIGHT}
            translation={translation}
            onBegin={() => begin(id)}
            onOver={(distance) => over(id, distance)}
            onEnd={end}
            onStep={(by) => step(id, by)}
          />
        )
      })}
    </ScrollView>
  )
}

interface RowProps {
  show: Show
  index: number
  count: number
  dragging: boolean
  /** How far the row's place has moved from where the drag began, so it can stay under the finger. */
  shift: number
  translation: SharedValue<number>
  onBegin: () => void
  onOver: (distance: number) => void
  onEnd: () => void
  onStep: (by: number) => void
}

function ArrangeRow({
  show,
  index,
  count,
  dragging,
  shift,
  translation,
  onBegin,
  onOver,
  onEnd,
  onStep,
}: RowProps) {
  const pan = Gesture.Pan()
    .onBegin(() => {
      "worklet"
      scheduleOnRN(onBegin)
    })
    .onUpdate((event) => {
      "worklet"
      translation.set(event.translationY)
      scheduleOnRN(onOver, event.translationY)
    })
    .onFinalize(() => {
      "worklet"
      scheduleOnRN(onEnd)
    })

  const style = useAnimatedStyle(() =>
    dragging
      ? { transform: [{ translateY: translation.get() - shift }], zIndex: 2 }
      : { transform: [{ translateY: 0 }], zIndex: 0 },
  )

  return (
    <Animated.View
      className={`border-border bg-background flex-row items-center gap-3 border-b ${
        dragging ? "shadow-lg" : ""
      }`}
      style={[{ height: ROW_HEIGHT }, style]}
      accessible
      accessibilityLabel={`${show.title}, place ${index + 1} of ${count}`}
      accessibilityActions={[
        { name: "decrement", label: "Move up" },
        { name: "increment", label: "Move down" },
      ]}
      onAccessibilityAction={(event) => {
        if (event.nativeEvent.actionName === "decrement") onStep(-1)
        else if (event.nativeEvent.actionName === "increment") onStep(1)
      }}
    >
      <Artwork uri={show.imageUrl} size={48} />
      <Text className="flex-1 font-semibold" numberOfLines={2}>
        {show.title}
      </Text>
      <GestureDetector gesture={pan}>
        <View
          className="size-11 items-center justify-center"
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          <Icon as={GripVertical} size={22} className="text-muted-foreground" />
        </View>
      </GestureDetector>
    </Animated.View>
  )
}
