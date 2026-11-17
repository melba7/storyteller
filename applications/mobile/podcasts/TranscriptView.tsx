// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import {
  ChevronDown,
  ChevronUp,
  Pause,
  Play,
  Search,
  X,
} from "lucide-react-native"
import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react"
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  TextInput,
  View,
} from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { player, usePlayer } from "@/modules/podcasts/playerInstance"
import { type TranscriptLine } from "@/modules/podcasts/transcriptFormats"
import {
  lineAt,
  lineTimeLabel,
  searchLines,
  speakerChanges,
  stepMatch,
} from "@/modules/podcasts/transcriptLines"

import { useTranscriptLines } from "./useTranscriptLines"

/** Where the playing line sits when the list follows along: about a third from the top. */
const FOLLOW_POSITION = 0.33

interface Props {
  episode: StoredEpisode
}

/**
 * The transcript, full height under the player's top bar: the line playing is highlighted
 * and kept about a third from the top, a tap on a line plays from there, scrolling by hand
 * stops the following until "Follow along" is pressed, and a search field finds words.
 */
export function TranscriptView({ episode }: Props) {
  const state = useTranscriptLines(episode)
  if (state.status === "loading") {
    return (
      <View className="flex-1 items-center justify-center">
        <ActivityIndicator
          color="#ffffff"
          accessibilityLabel="Loading the transcript"
        />
      </View>
    )
  }
  if (state.lines === null) {
    return (
      <View className="flex-1 items-center justify-center px-8">
        <Text
          className="text-center text-base text-white/80"
          accessibilityRole="alert"
        >
          {state.reason}
        </Text>
      </View>
    )
  }
  return <Lines lines={state.lines} episode={episode} />
}

function Lines({
  lines,
  episode,
}: {
  lines: TranscriptLine[]
  episode: StoredEpisode
}) {
  const view = usePlayer()
  const listRef = useRef<FlatList<TranscriptLine>>(null)
  const [following, setFollowing] = useState(true)
  const [query, setQuery] = useState("")
  const [current, setCurrent] = useState<number | null>(null)
  const matches = useMemo(() => searchLines(lines, query), [lines, query])
  const matchSet = useMemo(() => new Set(matches), [matches])
  // Only while this episode is the one loaded does the playing position mean anything here.
  const playingHere = view.episode?.id === episode.id
  const playing = playingHere ? lineAt(lines, view.position) : -1

  const scrollTo = useCallback((index: number) => {
    listRef.current?.scrollToIndex({
      index,
      viewPosition: FOLLOW_POSITION,
      animated: true,
    })
  }, [])

  useEffect(() => {
    if (following && playing >= 0) scrollTo(playing)
  }, [following, playing, scrollTo])

  // A new search starts at its first match, and looking at a match stops the following.
  useEffect(() => {
    const first = matches[0] ?? null
    setCurrent(first)
    if (first !== null) {
      setFollowing(false)
      scrollTo(first)
    }
  }, [matches, scrollTo])

  function step(direction: 1 | -1) {
    const next = stepMatch(matches, current, direction)
    if (next === null) return
    setCurrent(next)
    setFollowing(false)
    scrollTo(next)
  }

  async function playFrom(line: TranscriptLine) {
    if (!view.episode || view.episode.id !== episode.id || !view.loaded) {
      await player.playEpisode(episode, view.show)
      await player.seekTo(line.start)
      return
    }
    await player.seekTo(line.start)
    if (!view.isPlaying) await player.togglePlayPause()
  }

  function followAlong() {
    setFollowing(true)
    if (playing >= 0) scrollTo(playing)
  }

  return (
    <View className="flex-1">
      <View className="flex-row items-center gap-2 px-4 pb-2">
        <View className="flex-1 flex-row items-center gap-2 rounded-full bg-white/15 px-3">
          <Icon as={Search} size={16} className="text-white/70" />
          <TextInput
            className="min-h-10 flex-1 text-base text-white"
            placeholder="Search the transcript"
            placeholderTextColor="rgba(255,255,255,0.5)"
            value={query}
            onChangeText={setQuery}
            returnKeyType="search"
            autoCorrect={false}
            autoCapitalize="none"
            accessibilityLabel="Search the transcript"
          />
          {query !== "" ? (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Clear the search"
              onPress={() => setQuery("")}
              hitSlop={8}
            >
              <Icon as={X} size={16} className="text-white/70" />
            </Pressable>
          ) : null}
        </View>
        {query.trim() !== "" ? (
          <>
            <Text
              className="min-w-12 text-center text-sm text-white/70"
              accessibilityLiveRegion="polite"
            >
              {matches.length === 0
                ? "None"
                : `${Math.max(0, matches.indexOf(current ?? -1)) + 1} of ${matches.length}`}
            </Text>
            <Pressable
              className="size-10 items-center justify-center active:opacity-60"
              accessibilityRole="button"
              accessibilityLabel="Previous match"
              disabled={matches.length === 0}
              onPress={() => step(-1)}
            >
              <Icon as={ChevronUp} size={24} className="text-white" />
            </Pressable>
            <Pressable
              className="size-10 items-center justify-center active:opacity-60"
              accessibilityRole="button"
              accessibilityLabel="Next match"
              disabled={matches.length === 0}
              onPress={() => step(1)}
            >
              <Icon as={ChevronDown} size={24} className="text-white" />
            </Pressable>
          </>
        ) : null}
      </View>

      <FlatList
        ref={listRef}
        data={lines}
        extraData={[playing, current, matchSet]}
        keyExtractor={(_, index) => String(index)}
        contentContainerClassName="px-safe-or-4 pb-24"
        onScrollBeginDrag={() => setFollowing(false)}
        onScrollToIndexFailed={(info) => {
          // The row is not drawn yet: go near it, then try again.
          listRef.current?.scrollToOffset({
            offset: info.averageItemLength * info.index,
            animated: false,
          })
          setTimeout(() => scrollTo(info.index), 50)
        }}
        renderItem={({ item, index }) => (
          <Row
            line={item}
            showSpeaker={speakerChanges(lines, index)}
            active={index === playing}
            matched={matchSet.has(index)}
            focused={index === current && matchSet.has(index)}
            onPress={() => void playFrom(item)}
          />
        )}
      />

      <View className="absolute inset-x-0 bottom-0 flex-row items-center justify-between px-4 pb-4">
        {!following && playingHere ? (
          <Pressable
            className="rounded-full bg-white px-4 py-2 active:opacity-80"
            accessibilityRole="button"
            accessibilityLabel="Follow along"
            onPress={followAlong}
          >
            <Text className="font-semibold text-black">Follow along</Text>
          </Pressable>
        ) : (
          <View />
        )}
        <Pressable
          className="size-14 items-center justify-center rounded-full bg-white active:opacity-80"
          accessibilityRole="button"
          accessibilityLabel={playingHere && view.isPlaying ? "Pause" : "Play"}
          onPress={() => void player.togglePlayPause()}
        >
          <Icon
            as={playingHere && view.isPlaying ? Pause : Play}
            size={26}
            className="text-black"
            fill="#000000"
          />
        </Pressable>
      </View>
    </View>
  )
}

const Row = memo(function Row({
  line,
  showSpeaker,
  active,
  matched,
  focused,
  onPress,
}: {
  line: TranscriptLine
  showSpeaker: boolean
  active: boolean
  matched: boolean
  focused: boolean
  onPress: () => void
}) {
  return (
    <View>
      {showSpeaker ? (
        <Text className="pt-4 pb-1 text-sm font-semibold text-white/60">
          {line.speaker}
        </Text>
      ) : null}
      <Pressable
        className={`rounded-lg px-2 py-2 active:bg-white/10 ${
          focused ? "bg-yellow-300/40" : matched ? "bg-yellow-300/20" : ""
        }`}
        accessibilityRole="button"
        accessibilityLabel={`${lineTimeLabel(line.start)}. ${line.text}`}
        accessibilityHint="Plays from here"
        accessibilityState={{ selected: active }}
        onPress={onPress}
      >
        <Text
          className={`text-lg leading-7 ${
            active ? "font-semibold text-white" : "text-white/55"
          }`}
        >
          {line.text}
        </Text>
      </Pressable>
    </View>
  )
})
