// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Link } from "expo-router"
import { type ReactElement } from "react"

import { type PodcastHref } from "@/modules/podcasts/routes"

/**
 * Opens `href` when its single child is pressed, with the iOS zoom transition: the child (an
 * artwork tile) grows into the page, whose artwork is the matching `Link.AppleZoomTarget`.
 * The child keeps its own press feedback and accessibility.
 */
export function ZoomLink({
  href,
  children,
}: {
  href: PodcastHref
  children: ReactElement
}) {
  return (
    <Link href={href} asChild>
      <Link.AppleZoom>{children}</Link.AppleZoom>
    </Link>
  )
}
