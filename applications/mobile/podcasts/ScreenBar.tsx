// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter } from "expo-router"
import { Children, Fragment, type ReactNode, isValidElement } from "react"
import { ScrollView } from "react-native"
import { useCSSVariable } from "uniwind"

import { ACCOUNT_HREF } from "@/modules/podcasts/routes"

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
  /**
   * The round account button at the top right (a tab root's): it opens Profile as a sheet.
   * It sits after any `right` items.
   */
  account?: boolean
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
 * the system font, bold; `left` and `right` fill the header's toolbar. A large title shrinks only
 * when the screen's first child is a scroll view with `contentInsetAdjustmentBehavior`
 * "automatic".
 */
export function ScreenBar({
  title,
  left,
  right,
  large = false,
  account = false,
  titleHidden = false,
}: Props) {
  const router = useRouter()
  const foreground = useCSSVariable("--color-foreground") as string
  const leftItems = toolbarItems(left)
  const rightItems = [
    ...toolbarItems(right),
    ...(account
      ? [
          <Stack.Toolbar.Button
            key="account"
            icon="person.crop.circle"
            accessibilityLabel="Account and settings"
            onPress={() => router.push(ACCOUNT_HREF)}
          />,
        ]
      : []),
  ]
  return (
    <>
      {/* A hidden title is drawn in no colour rather than swapped for a custom header title:
          options set through Stack.Screen stay after it unmounts, so the title could never
          come back. VoiceOver still reads it. */}
      <Stack.Title
        large={large}
        style={{
          fontWeight: "700",
          color: titleHidden ? "transparent" : foreground,
        }}
        largeStyle={{ fontWeight: "700", color: foreground }}
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

/**
 * Wraps a screen's loading or message state, which has no list of its own, so the content
 * starts below the transparent header, not under it.
 */
export function BelowBar({ children }: { children: ReactNode }) {
  return (
    <ScrollView
      className="bg-background flex-1"
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ flexGrow: 1 }}
    >
      {children}
    </ScrollView>
  )
}
