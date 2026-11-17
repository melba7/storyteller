// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Check, Share2 } from "lucide-react-native"
import { useRef, useState } from "react"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { needsMore, showMeta } from "@/modules/podcasts/episodeLook"
import { type Show } from "@/modules/podcasts/library"
import { showShare } from "@/modules/podcasts/share"

import { Artwork } from "./Artwork"
import { shareContent } from "./ShareButton"
import { useArtworkColor, useWashStyle } from "./useWash"

interface Props {
  show: Show
  problem: string | null
  /** Called when the listener taps Following; the screen asks to confirm. */
  onUnfollow?: () => void
  /** For a show not in the library yet: shows Follow, in place of Following. */
  onFollow?: () => void
  /** The follow is being saved. */
  busy?: boolean
  /** How many episodes the show has, for the meta line; null while unknown. */
  episodeCount?: number | null
  /**
   * Called with how far down the page (from the top of the list) the show's title ends, once
   * it is laid out and again if it moves. The screen uses it to know when the title has
   * scrolled under the bar.
   */
  onTitleBottom?: (bottom: number) => void
}

/** Room above the header that the wash also covers, so it runs behind a transparent bar. */
const WASH_ABOVE = 300
/** How far the wash runs below the artwork. */
const WASH_BELOW = 32
const ARTWORK = 200

/**
 * The top of a show's page: a wash from the artwork's colour, the artwork, title, author, a
 * meta line, Follow or Following beside a share button, and the description.
 */
export function ShowHeader({
  show,
  problem,
  onUnfollow,
  onFollow,
  busy = false,
  episodeCount = null,
  onTitleBottom,
}: Props) {
  // The title group's top and the title's bottom inside it, which arrive as two layouts.
  const groupTop = useRef<number | null>(null)
  const titleEnd = useRef<number | null>(null)
  function reportTitleBottom() {
    if (groupTop.current !== null && titleEnd.current !== null) {
      onTitleBottom?.(groupTop.current + titleEnd.current)
    }
  }
  const [expanded, setExpanded] = useState(false)
  const long = needsMore(show.description)
  // A preview's show isn't in the database, so its colour is measured but not saved.
  const wash = useWashStyle(useArtworkColor(show, !onFollow))
  const meta = showMeta(show.categories, episodeCount)
  return (
    <View className="items-center gap-3 pt-2 pb-4">
      {wash ? (
        <View
          pointerEvents="none"
          style={[
            {
              position: "absolute",
              top: -WASH_ABOVE,
              left: -64,
              right: -64,
              height: WASH_ABOVE + 8 + ARTWORK + WASH_BELOW,
            },
            wash,
          ]}
        />
      ) : null}
      <View
        className="rounded-2xl"
        style={{ boxShadow: "0 8px 24px rgba(0, 0, 0, 0.25)" }}
      >
        <Artwork uri={show.imageUrl} size={ARTWORK} className="rounded-2xl" />
      </View>
      <View
        className="items-center gap-1"
        onLayout={(event) => {
          groupTop.current = event.nativeEvent.layout.y
          reportTitleBottom()
        }}
      >
        <Text
          className="text-center text-2xl font-bold"
          accessibilityRole="header"
          onLayout={(event) => {
            const { y, height } = event.nativeEvent.layout
            titleEnd.current = y + height
            reportTitleBottom()
          }}
        >
          {show.title}
        </Text>
        {show.author ? (
          <Text className="text-muted-foreground text-center text-base">
            {show.author}
          </Text>
        ) : null}
        {meta ? (
          <Text className="text-muted-foreground text-center text-sm">
            {meta}
          </Text>
        ) : null}
      </View>
      <View className="flex-row items-center gap-3">
        {onFollow ? (
          <Pressable
            className="bg-primary h-11 min-w-32 flex-row items-center justify-center gap-2 rounded-full px-6 active:opacity-80"
            accessibilityRole="button"
            accessibilityLabel={`Follow ${show.title}`}
            disabled={busy}
            onPress={onFollow}
          >
            {busy ? (
              <ActivityIndicator accessibilityLabel="Following" />
            ) : (
              <Text className="text-primary-foreground font-semibold">
                Follow
              </Text>
            )}
          </Pressable>
        ) : (
          // A show in the library: tapping asks to unfollow.
          <Pressable
            className="bg-secondary h-11 min-w-32 flex-row items-center justify-center gap-2 rounded-full px-6 active:opacity-80"
            accessibilityRole="button"
            accessibilityLabel={`Following ${show.title}. Tap to unfollow`}
            onPress={onUnfollow}
          >
            <Icon as={Check} size={18} className="text-primary" />
            <Text className="font-semibold">Following</Text>
          </Pressable>
        )}
        <Pressable
          className="bg-secondary size-11 items-center justify-center rounded-full active:opacity-80"
          accessibilityRole="button"
          accessibilityLabel={`Share ${show.title}`}
          onPress={() => void shareContent(() => showShare(show))}
        >
          <Icon as={Share2} size={20} className="text-primary" />
        </Pressable>
      </View>
      {show.description ? (
        <View className="w-full gap-1">
          <Text className="text-sm" numberOfLines={expanded ? undefined : 3}>
            {show.description}
          </Text>
          {long ? (
            <Pressable
              className="self-end py-1"
              accessibilityRole="button"
              accessibilityLabel={
                expanded
                  ? "Show less of the description"
                  : "Show more of the description"
              }
              onPress={() => setExpanded((value) => !value)}
            >
              <Text className="text-primary text-sm font-semibold">
                {expanded ? "Less" : "More"}
              </Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}
      {problem ? (
        <Text className="text-destructive text-sm" accessibilityRole="alert">
          {problem}
        </Text>
      ) : null}
    </View>
  )
}
