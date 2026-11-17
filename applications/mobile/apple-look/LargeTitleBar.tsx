// LOFI-FORK: the Apple Podcasts look for the Books side (see FORK.md).
import { Stack } from "expo-router"
import { Children, Fragment, type ReactNode, isValidElement } from "react"
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
  /** A large title that shrinks on scroll; otherwise a small inline one. */
  large?: boolean
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
 * The top bar of a Books screen: the stack's native header with the title in the system
 * font. `left` and `right` fill the header's toolbar. A large title shrinks only when the
 * screen's first child is a scroll view with `contentInsetAdjustmentBehavior` "automatic".
 */
export function LargeTitleBar({ title, left, right, large = false }: Props) {
  const foreground = useCSSVariable("--color-foreground") as string
  const leftItems = toolbarItems(left)
  const rightItems = toolbarItems(right)
  return (
    <>
      <Stack.Title
        large={large}
        style={{ color: foreground }}
        largeStyle={{ color: foreground }}
      >
        {title}
      </Stack.Title>
      {leftItems.length > 0 ? (
        <Stack.Toolbar placement="left">{leftItems}</Stack.Toolbar>
      ) : null}
      {rightItems.length > 0 ? (
        <Stack.Toolbar placement="right">{rightItems}</Stack.Toolbar>
      ) : null}
    </>
  )
}
