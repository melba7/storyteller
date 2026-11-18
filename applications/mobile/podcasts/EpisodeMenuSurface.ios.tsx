// LOFI-FORK: the podcasts section's screens (see FORK.md).
import {
  Button,
  ControlGroup,
  Host,
  Menu,
  RNHostView,
  Section,
} from "@expo/ui/swift-ui"
import { tint as tintModifier } from "@expo/ui/swift-ui/modifiers"
import { Fragment } from "react"
import { type SFSymbol } from "sf-symbols-typescript"

import { type MenuItem } from "@/modules/podcasts/episodeMenuModel"

import { type SurfaceProps } from "./episodeMenuSurface.types"

function entry(item: MenuItem, onSelect: (id: string) => void) {
  return (
    <Button
      key={item.id}
      label={item.title}
      systemImage={item.icon as SFSymbol}
      {...(item.destructive ? { role: "destructive" as const } : {})}
      onPress={() => onSelect(item.id)}
    />
  )
}

/**
 * The native iOS menu with Apple's layout: a ControlGroup (drawn by iOS as a row of big
 * buttons inside a menu) for Save and Share, then a Section per group, which iOS separates
 * with a line.
 */
export function EpisodeMenuSurface({
  layout,
  onSelect,
  tint,
  children,
}: SurfaceProps) {
  return (
    <Host
      matchContents
      ignoreSafeArea="all"
      {...(tint ? { modifiers: [tintModifier(tint)] } : {})}
    >
      <Menu
        label={
          <RNHostView matchContents>
            <Fragment>{children}</Fragment>
          </RNHostView>
        }
      >
        <ControlGroup>
          {layout.top.map((item) => entry(item, onSelect))}
        </ControlGroup>
        {layout.groups.map((group, index) => (
          <Section key={index}>
            {group.map((item) => entry(item, onSelect))}
          </Section>
        ))}
      </Menu>
    </Host>
  )
}
