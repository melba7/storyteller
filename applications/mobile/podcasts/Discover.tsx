// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { Link } from "lucide-react-native"
import { useEffect, useRef, useState } from "react"
import { ActivityIndicator, Pressable, ScrollView, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  type DirectoryShow,
  searchDirectory,
} from "@/modules/podcasts/directory"
import { followLink } from "@/modules/podcasts/followLink"
import { isFollowLink } from "@/modules/podcasts/followLinkText"
import { Podcasts } from "@/modules/podcasts/index"
import { readableError } from "@/modules/podcasts/nativeError"
import { episodeHref, previewHref, showHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { DiscoverBrowse } from "./DiscoverBrowse"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useStatusBarStyle } from "./usePodcastsTheme"

const SEARCH_DELAY_MS = 400

export function Discover() {
  const router = useRouter()
  const segments = useSegments()
  const [term, setTerm] = useState("")
  const [results, setResults] = useState<DirectoryShow[]>([])
  const [searching, setSearching] = useState(false)
  const [searchError, setSearchError] = useState<string | null>(null)
  // Set while the link typed into the search bar is being followed.
  const [adding, setAdding] = useState<string | null>(null)
  const [addError, setAddError] = useState<string | null>(null)
  const latestSearch = useRef(0)

  useEffect(() => {
    // A link is followed, not searched for.
    const trimmed = isFollowLink(term) ? "" : term.trim()
    const search = ++latestSearch.current
    if (trimmed === "") {
      setResults([])
      setSearching(false)
      setSearchError(null)
      return
    }
    setSearching(true)
    const timer = setTimeout(() => {
      searchDirectory(trimmed).then(
        (found) => {
          if (search !== latestSearch.current) return
          setResults(found)
          setSearchError(null)
          setSearching(false)
        },
        (cause: unknown) => {
          if (search !== latestSearch.current) return
          setResults([])
          setSearchError(readableError(cause))
          setSearching(false)
        },
      )
    }, SEARCH_DELAY_MS)
    return () => clearTimeout(timer)
  }, [term])

  async function add(input: string, busyKey: string) {
    if (adding) return
    setAdding(busyKey)
    setAddError(null)
    try {
      const { show, episodeId } = await followLink(input)
      // Back from the show returns here, to Discover. An Apple link to an episode opens its
      // card over the show.
      router.push(showHref(segments, show.id))
      if (episodeId) router.push(episodeHref(segments, episodeId))
      setAdding(null)
    } catch (cause) {
      setAddError(readableError(cause))
      setAdding(null)
    }
  }

  const canAdd = Podcasts !== null && adding === null
  const typed = term.trim() !== ""
  const isLink = isFollowLink(term)
  const statusBarStyle = useStatusBarStyle()

  return (
    <>
      <ScrollView
        className="bg-background flex-1"
        contentContainerClassName="px-safe-or-4 gap-3"
        contentInsetAdjustmentBehavior="automatic"
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
      >
        {Podcasts === null ? (
          <Text className="text-muted-foreground text-sm">
            Podcasts need the iOS app. You can search here, but adding a show
            only works there.
          </Text>
        ) : null}
        {addError ? (
          <Text className="text-destructive text-sm" accessibilityRole="alert">
            {addError}
          </Text>
        ) : null}

        {isLink ? (
          <Pressable
            className="bg-secondary min-h-14 flex-row items-center gap-3 rounded-2xl px-4 py-3 active:opacity-70"
            accessibilityRole="button"
            accessibilityLabel="Follow this link"
            accessibilityState={{ disabled: !canAdd }}
            disabled={!canAdd}
            onPress={() => add(term, "link")}
          >
            <Icon as={Link} size={22} className="text-primary" />
            <View className="flex-1">
              <Text className="font-semibold">Follow this link</Text>
              <Text className="text-muted-foreground text-sm" numberOfLines={1}>
                {term.trim()}
              </Text>
            </View>
            {adding === "link" ? <ActivityIndicator /> : null}
          </Pressable>
        ) : null}
        {searching ? (
          <ActivityIndicator accessibilityLabel="Searching" />
        ) : searchError ? (
          <Text className="text-destructive text-sm">{searchError}</Text>
        ) : typed && !isLink && results.length === 0 ? (
          <Text className="text-muted-foreground text-sm">
            No podcasts found.
          </Text>
        ) : null}
        {results.map((show) => (
          <Pressable
            key={show.id}
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
                <Text
                  className="text-muted-foreground text-sm"
                  numberOfLines={1}
                >
                  {show.author}
                </Text>
              ) : null}
            </View>
          </Pressable>
        ))}

        {!typed ? (
          <View className="mt-4 pb-6">
            <DiscoverBrowse />
          </View>
        ) : null}
      </ScrollView>
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Discover"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
      />
      <Stack.SearchBar
        placeholder="Search podcasts or paste a link"
        autoCapitalize="none"
        hideWhenScrolling={false}
        onChangeText={(event) => setTerm(event.nativeEvent.text)}
        onCancelButtonPress={() => setTerm("")}
      />
    </>
  )
}
