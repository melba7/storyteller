// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { GripVertical } from "lucide-react-native"
import { type ReactNode, useRef, useState } from "react"
import { ScrollView, View } from "react-native"
import { Gesture, GestureDetector } from "react-native-gesture-handler"
import Animated, {
  type SharedValue,
  useAnimatedStyle,
  useSharedValue,
} from "react-native-reanimated"
import { scheduleOnRN } from "react-native-worklets"

import { Icon } from "@/components/ui/icon"
import { dropIndex, moveShow } from "@/modules/podcasts/arrange"

/** An extra VoiceOver action on a row, besides Move up and Move down. */
export type RowAction = { name: string; label: string }

interface ListProps {
  ids: string[]
  rowHeight: number
  onChange: (ids: string[]) => void
  /** The row's content, to the left of the drag handle. */
  renderContent: (id: string, index: number) => ReactNode
  /** What VoiceOver reads for a row. */
  label: (id: string, index: number, count: number) => string
  actions?: RowAction[]
  onAction?: (id: string, name: string) => void
  /** Shown above the rows, inside the scroll view, so a large title can shrink. */
  header?: ReactNode
  /** Shown below the rows, inside the scroll view. */
  footer?: ReactNode
  /** Called when a row is let go after it was moved to a new place. */
  onDrop?: () => void
  /**
   * Draws the list on its surroundings (transparent, no card colour) with these colours for
   * the row separators and the grip, as the player's queue does on the sheet. Without it the
   * list uses the theme's colours.
   */
  onSheet?: { line: string; grip: string } | undefined
}

/**
 * A list whose rows are dragged by their handle (or moved with VoiceOver's Move up and Move
 * down), shared by the arrange screen and Up Next. The dragged row's new place is kept here
 * while the finger is down, so a late change from the caller cannot put an older order back.
 * The new order is reported once through `onChange` when the row is let go; the caller keeps
 * the order.
 */
export function DragList({
  ids,
  rowHeight,
  onChange,
  renderContent,
  label,
  actions = [],
  onAction,
  header,
  footer,
  onDrop,
  onSheet,
}: ListProps) {
  // The row being dragged, where it started, and how far the finger has moved.
  const [dragging, setDragging] = useState<string | null>(null)
  const start = useRef(0)
  const moved = useRef(false)
  const translation = useSharedValue(0)
  const latest = useRef(ids)
  latest.current = ids
  // The order while a row is dragged; null otherwise, when the caller's order is shown.
  const [dragOrder, setDragOrder] = useState<string[] | null>(null)
  const dragged = useRef<string[] | null>(null)
  const shown = dragOrder ?? ids

  function begin(id: string) {
    const at = latest.current.indexOf(id)
    if (at < 0) return
    start.current = at
    moved.current = false
    dragged.current = [...latest.current]
    setDragging(id)
  }

  function over(id: string, distance: number) {
    const order = dragged.current
    if (order === null) return
    const from = order.indexOf(id)
    if (from < 0) return
    const to = dropIndex(start.current, distance, rowHeight, order.length)
    if (from !== to) {
      moved.current = true
      dragged.current = moveShow(order, from, to)
      setDragOrder(dragged.current)
    }
  }

  function end() {
    if (moved.current && dragged.current !== null) {
      onChange(dragged.current)
      onDrop?.()
    }
    moved.current = false
    dragged.current = null
    setDragOrder(null)
    setDragging(null)
    translation.set(0)
  }

  function step(id: string, by: number) {
    const from = latest.current.indexOf(id)
    onChange(moveShow(latest.current, from, from + by))
  }

  return (
    <ScrollView
      className={onSheet ? "flex-1" : "bg-background flex-1"}
      scrollEnabled={dragging === null}
      contentContainerClassName={onSheet ? "" : "px-safe-or-4"}
      contentInsetAdjustmentBehavior="automatic"
    >
      {header}
      {shown.map((id, index) => (
        <DragRow
          key={id}
          index={index}
          height={rowHeight}
          label={label(id, index, shown.length)}
          actions={actions}
          dragging={dragging === id}
          shift={(index - start.current) * rowHeight}
          translation={translation}
          onBegin={() => begin(id)}
          onOver={(distance) => over(id, distance)}
          onEnd={end}
          onStep={(by) => step(id, by)}
          onAction={(name) => onAction?.(id, name)}
          onSheet={onSheet}
        >
          {renderContent(id, index)}
        </DragRow>
      ))}
      {footer}
    </ScrollView>
  )
}

interface RowProps {
  children: ReactNode
  index: number
  height: number
  label: string
  actions: RowAction[]
  dragging: boolean
  /** How far the row's place has moved from where the drag began, so it can stay under the finger. */
  shift: number
  translation: SharedValue<number>
  onBegin: () => void
  onOver: (distance: number) => void
  onEnd: () => void
  onStep: (by: number) => void
  onAction: (name: string) => void
  onSheet?: { line: string; grip: string } | undefined
}

function DragRow({
  children,
  height,
  label,
  actions,
  dragging,
  shift,
  translation,
  onBegin,
  onOver,
  onEnd,
  onStep,
  onAction,
  onSheet,
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
      className={`flex-row items-center gap-3 border-b ${
        onSheet ? "" : "border-border bg-background"
      } ${dragging ? "shadow-lg" : ""}`}
      style={[
        { height },
        onSheet ? { borderBottomColor: onSheet.line } : null,
        style,
      ]}
      accessible
      accessibilityLabel={label}
      accessibilityActions={[
        { name: "decrement", label: "Move up" },
        { name: "increment", label: "Move down" },
        ...actions,
      ]}
      onAccessibilityAction={(event) => {
        const name = event.nativeEvent.actionName
        if (name === "decrement") onStep(-1)
        else if (name === "increment") onStep(1)
        else onAction(name)
      }}
    >
      <View className="h-full flex-1 justify-center">{children}</View>
      <GestureDetector gesture={pan}>
        <View
          className="size-11 items-center justify-center"
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          {onSheet ? (
            <Icon as={GripVertical} size={22} color={onSheet.grip} />
          ) : (
            <Icon
              as={GripVertical}
              size={22}
              className="text-muted-foreground"
            />
          )}
        </View>
      </GestureDetector>
    </Animated.View>
  )
}
