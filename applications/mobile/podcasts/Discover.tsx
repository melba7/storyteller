// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { useEffect, useRef, useState } from "react"
import { ActivityIndicator, Pressable, ScrollView, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
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
import { DiscoverBrowse } from "./DiscoverBrowse"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"

const SEARCH_DELAY_MS = 400

export function Discover() {
  const router = useRouter()
  const segments = useSegments()
  const [term, setTerm] = useState("")
  const [results, setResults] = useState<DirectoryShow[]>([])
  const [searching, setSearching] = useState(false)
  const [searchError, setSearchError] = useState<string | null>(null)
  const [link, setLink] = useState("")
  // Whether the pasted link is being followed now.
  const [adding, setAdding] = useState<string | null>(null)
  const [addError, setAddError] = useState<string | null>(null)
  const latestSearch = useRef(0)

  useEffect(() => {
    const trimmed = term.trim()
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

  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar
        title="Discover"
        left={<SectionMenuButton current="podcasts" />}
      />
      <ScrollView
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

        <Input
          accessibilityLabel="Search podcasts"
          placeholder="Search for a podcast"
          value={term}
          onChangeText={setTerm}
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="search"
          clearButtonMode="while-editing"
        />
        {searching ? (
          <ActivityIndicator accessibilityLabel="Searching" />
        ) : searchError ? (
          <Text className="text-destructive text-sm">{searchError}</Text>
        ) : term.trim() !== "" && results.length === 0 ? (
          <Text className="text-muted-foreground text-sm">
            No podcasts found.
          </Text>
        ) : null}
        {results.map((show) => (
          <Pressable
            key={show.id}
            className="active:bg-secondary flex-row items-center gap-3 rounded-md py-1"
            accessibilityRole="button"
            accessibilityLabel={`Preview ${show.title}`}
            onPress={() => router.push(previewHref(segments, show.feedUrl))}
          >
            <Artwork uri={show.imageUrl} size={56} />
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

        <Text className="mt-4 font-semibold">Paste a link</Text>
        <Input
          accessibilityLabel="RSS or Apple Podcasts link"
          placeholder="RSS or Apple Podcasts link"
          value={link}
          onChangeText={setLink}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
          returnKeyType="go"
          onSubmitEditing={() => {
            if (canAdd && link.trim() !== "") void add(link, "link")
          }}
        />
        <Button
          accessibilityLabel="Add this link"
          disabled={!canAdd || link.trim() === ""}
          onPress={() => add(link, "link")}
        >
          {adding === "link" ? <ActivityIndicator /> : <Text>Add</Text>}
        </Button>

        {term.trim() === "" ? (
          <View className="mt-4 pb-6">
            <DiscoverBrowse />
          </View>
        ) : null}
      </ScrollView>
    </View>
  )
}
