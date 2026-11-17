// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"
import { Children, Fragment, type ReactNode, isValidElement } from "react"
import { ScrollView } from "react-native"
import { useCSSVariable } from "uniwind"

interface Props {
  title: string
  /**
   * Toolbar items for the left side: `Stack.Toolbar.Button`, `Stack.Toolbar.Menu` or a
   * `Stack.Toolbar.View` around React content. Without it the native back button shows.
   */
  left?: ReactNode
  /** Toolbar items for the right side, as `left`. */
  right?: ReactNode
  /** A large title that shrinks on scroll (the tab roots); otherwise a small inline one. */
  large?: boolean
  /** Keeps the title for VoiceOver and the back button but draws none. */
  titleHidden?: boolean
}

/**
 * The elements of `node` with fragments opened up. A toolbar finds its buttons and menus
 * by their type among its direct children, so a fragment around them would hide them.
 */
function toolbarItems(node: ReactNode): ReactNode[] {
  return Children.toArray(node).flatMap((child) =>
    isValidElement<{ children?: ReactNode }>(child) && child.type === Fragment
      ? toolbarItems(child.props.children)
      : [child],
  )
}

/**
 * The top bar of a podcasts screen: the stack's native header. The title is drawn by iOS in
 * the brand serif; `left` and `right` fill the header's toolbar. A large title shrinks only
 * when the screen's first child is a scroll view with `contentInsetAdjustmentBehavior`
 * "automatic".
 */
export function ScreenBar({
  title,
  left,
  right,
  large = false,
  titleHidden = false,
}: Props) {
  const foreground = useCSSVariable("--color-foreground") as string
  const leftItems = toolbarItems(left)
  const rightItems = toolbarItems(right)
  return (
    <>
      {titleHidden ? (
        <Stack.Screen options={{ title, headerTitle: () => null }} />
      ) : (
        <Stack.Title
          large={large}
          style={{ fontFamily: "YoungSerif", color: foreground }}
          largeStyle={{ fontFamily: "YoungSerif", color: foreground }}
        >
          {title}
        </Stack.Title>
      )}
      {leftItems.length > 0 ? (
        <Stack.Toolbar placement="left">{leftItems}</Stack.Toolbar>
      ) : null}
      {rightItems.length > 0 ? (
        <Stack.Toolbar placement="right">{rightItems}</Stack.Toolbar>
      ) : null}
    </>
  )
}

/**
 * Wraps a screen's loading or message state, which has no list of its own, so the content
 * starts below the transparent header, not under it.
 */
export function BelowBar({ children }: { children: ReactNode }) {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ flexGrow: 1 }}
    >
      {children}
    </ScrollView>
  )
}
