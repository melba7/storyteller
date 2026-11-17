// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { Link } from "lucide-react-native"
import { useState } from "react"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  type DirectoryShow,
  searchDirectory,
} from "@/modules/podcasts/directory"
import { followLink } from "@/modules/podcasts/followLink"
import { Podcasts } from "@/modules/podcasts/index"
import { readableError } from "@/modules/podcasts/nativeError"
import { episodeHref, previewHref, showHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { useDebouncedSearch } from "./useDebouncedSearch"

/** Searches Apple's directory for shows while `active` and the words are not a link. */
export function useShowSearch(term: string, active: boolean) {
  return useDebouncedSearch<DirectoryShow>(
    active ? term : "",
    searchDirectory,
    400,
  )
}

/** One show found in the directory; it opens a preview, from where it can be followed. */
export function ShowResult({ show }: { show: DirectoryShow }) {
  const router = useRouter()
  const segments = useSegments()
  return (
    <Pressable
      className="active:bg-secondary flex-row items-center gap-3 rounded-xl py-1"
      accessibilityRole="button"
      accessibilityLabel={`Preview ${show.title}`}
      onPress={() => router.push(previewHref(segments, show.feedUrl))}
    >
      <Artwork uri={show.imageUrl} size={64} />
      <View className="flex-1">
        <Text className="font-semibold" numberOfLines={2}>
          {show.title}
        </Text>
        {show.author ? (
          <Text className="text-muted-foreground text-sm" numberOfLines={1}>
            {show.author}
          </Text>
        ) : null}
      </View>
    </Pressable>
  )
}

/**
 * "Follow this link" for a pasted feed or Apple Podcasts link: it adds the show and opens its
 * page (an Apple link to an episode opens the episode's card over it).
 */
export function FollowLinkRow({ term }: { term: string }) {
  const router = useRouter()
  const segments = useSegments()
  const [adding, setAdding] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const canAdd = Podcasts !== null && !adding

  async function add() {
    if (!canAdd) return
    setAdding(true)
    setError(null)
    try {
      const { show, episodeId } = await followLink(term)
      // Back from the show returns to Search.
      router.push(showHref(segments, show.id))
      if (episodeId) router.push(episodeHref(segments, episodeId))
    } catch (cause) {
      setError(readableError(cause))
    } finally {
      setAdding(false)
    }
  }

  return (
    <View className="gap-2">
      {Podcasts === null ? (
        <Text className="text-muted-foreground text-sm">
          Podcasts need the iOS app. You can search here, but adding a show only
          works there.
        </Text>
      ) : null}
      {error ? (
        <Text className="text-destructive text-sm" accessibilityRole="alert">
          {error}
        </Text>
      ) : null}
      <Pressable
        className="bg-secondary min-h-14 flex-row items-center gap-3 rounded-2xl px-4 py-3 active:opacity-70"
        accessibilityRole="button"
        accessibilityLabel="Follow this link"
        accessibilityState={{ disabled: !canAdd }}
        disabled={!canAdd}
        onPress={() => void add()}
      >
        <Icon as={Link} size={22} className="text-primary" />
        <View className="flex-1">
          <Text className="font-semibold">Follow this link</Text>
          <Text className="text-muted-foreground text-sm" numberOfLines={1}>
            {term.trim()}
          </Text>
        </View>
        {adding ? <ActivityIndicator /> : null}
      </Pressable>
    </View>
  )
}
