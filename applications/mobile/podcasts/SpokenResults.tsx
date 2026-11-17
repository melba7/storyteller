// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"
import { Alert, FlatList, Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { readableError } from "@/modules/podcasts/nativeError"
import { player } from "@/modules/podcasts/playerInstance"
import { SPOKEN_EMPTY_NOTE, spokenTime } from "@/modules/podcasts/spoken"
import { type SpokenResult } from "@/modules/podcasts/spokenSearch"
import { listTranscripts } from "@/modules/podcasts/transcriptsNative"

import { Artwork } from "./Artwork"

/** True once at least one episode on the phone has a finished transcript (null: not known yet). */
function useAnyTranscribed(): boolean | null {
  const [any, setAny] = useState<boolean | null>(null)
  useEffect(() => {
    let cancelled = false
    listTranscripts().then(
      (infos) => {
        if (!cancelled) setAny(infos.some((info) => info.state === "done"))
      },
      () => {
        if (!cancelled) setAny(null)
      },
    )
    return () => {
      cancelled = true
    }
  }, [])
  return any
}

function playFrom({ episode, show }: SpokenResult, seconds: number) {
  player
    .playFrom(episode, show, seconds)
    .catch((cause: unknown) =>
      Alert.alert("Couldn't play from there", readableError(cause)),
    )
}

/** The spoken-word results: each episode, then the lines where the words were said. */
export function SpokenResults({
  results,
  typed,
  waiting,
}: {
  results: SpokenResult[]
  typed: boolean
  /** A search is running or has failed, so the screen says that instead. */
  waiting: boolean
}) {
  const anyTranscribed = useAnyTranscribed()
  return (
    <>
      {anyTranscribed === false ? (
        <Text className="text-muted-foreground px-8 py-6 text-center text-sm">
          {SPOKEN_EMPTY_NOTE}
        </Text>
      ) : typed && !waiting && results.length === 0 ? (
        <Text className="text-muted-foreground px-8 py-6 text-center text-sm">
          Nothing said like that in the episodes on this phone.
        </Text>
      ) : null}
      <FlatList
        data={results}
        keyExtractor={(group) => group.episode.id}
        contentContainerClassName="px-safe-or-4 gap-4 pb-6"
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        renderItem={({ item }) => (
          <View className="gap-1">
            <View className="flex-row items-center gap-3">
              <Artwork
                uri={item.episode.imageUrl ?? item.show?.imageUrl ?? null}
                size={40}
              />
              <View className="flex-1">
                <Text className="font-semibold" numberOfLines={2}>
                  {item.episode.title}
                </Text>
                {item.show ? (
                  <Text
                    className="text-muted-foreground text-sm"
                    numberOfLines={1}
                  >
                    {item.show.title}
                  </Text>
                ) : null}
              </View>
            </View>
            {item.hits.map((hit) => (
              <Pressable
                key={hit.seconds}
                className="active:bg-secondary rounded-md px-1 py-1"
                accessibilityRole="button"
                accessibilityLabel={`Play ${item.episode.title} from ${spokenTime(hit.seconds)}`}
                onPress={() => playFrom(item, hit.seconds)}
              >
                <Text className="text-muted-foreground text-xs">
                  {spokenTime(hit.seconds)}
                </Text>
                <Text className="text-sm" numberOfLines={3}>
                  {[hit.before, hit.text, hit.after]
                    .filter((line) => line !== "")
                    .join(" ")}
                </Text>
              </Pressable>
            ))}
          </View>
        )}
      />
    </>
  )
}
