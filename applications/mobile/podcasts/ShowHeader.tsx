// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Check } from "lucide-react-native"
import { useState } from "react"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { needsMore } from "@/modules/podcasts/episodeLook"
import { type Show } from "@/modules/podcasts/library"

import { Artwork } from "./Artwork"

interface Props {
  show: Show
  problem: string | null
  /** Called when the listener taps Following; the screen asks to confirm. */
  onUnfollow?: () => void
  /** For a show not in the library yet: shows Follow, in place of Following. */
  onFollow?: () => void
  /** The follow is being saved. */
  busy?: boolean
}

/** The top of a show's page: big artwork, title, author, Following, and the description. */
export function ShowHeader({
  show,
  problem,
  onUnfollow,
  onFollow,
  busy = false,
}: Props) {
  const [expanded, setExpanded] = useState(false)
  const long = needsMore(show.description)
  return (
    <View className="items-center gap-3 pb-4">
      <Artwork uri={show.imageUrl} size={200} className="rounded-xl" />
      <View className="items-center gap-1">
        <Text variant="h4" className="text-center">
          {show.title}
        </Text>
        {show.author ? (
          <Text className="text-muted-foreground text-center">
            {show.author}
          </Text>
        ) : null}
      </View>
      {onFollow ? (
        <Button
          accessibilityLabel={`Follow ${show.title}`}
          disabled={busy}
          onPress={onFollow}
        >
          {busy ? <ActivityIndicator /> : <Text>Follow</Text>}
        </Button>
      ) : (
        // A show in the library: tapping asks to unfollow.
        <Button
          variant="outline"
          accessibilityLabel={`Following ${show.title}. Tap to unfollow`}
          onPress={onUnfollow}
        >
          <Icon as={Check} size={18} className="text-primary" />
          <Text>Following</Text>
        </Button>
      )}
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
