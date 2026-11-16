// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { Plus } from "lucide-react-native"
import { useState } from "react"
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  View,
} from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { refreshAllShows } from "@/modules/podcasts/db"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"

import { Artwork } from "./Artwork"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useShows } from "./hooks"

export function PodcastsHome() {
  const router = useRouter()
  const shows = useShows()
  const [refreshing, setRefreshing] = useState(false)
  const [refreshProblem, setRefreshProblem] = useState<string | null>(null)

  function openAdd() {
    router.push("/podcasts/add")
  }

  async function refresh() {
    setRefreshing(true)
    setRefreshProblem(null)
    try {
      const { failed } = await refreshAllShows()
      if (failed.length > 0) {
        setRefreshProblem(`Couldn't refresh ${failed.join(", ")}.`)
      }
    } catch (cause) {
      setRefreshProblem(readableError(cause))
    } finally {
      setRefreshing(false)
    }
  }

  return (
    <View className="pt-safe bg-background flex-1">
      <StatusBar verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        title="Podcasts"
        left={<SectionMenuButton current="podcasts" />}
        right={
          <Button
            variant="ghost"
            size="sm"
            accessibilityLabel="Add a podcast"
            onPress={openAdd}
          >
            <Icon as={Plus} size={18} className="text-primary" />
            <Text className="text-primary">Add</Text>
          </Button>
        }
      />
      {Podcasts === null ? (
        <Message
          title="Podcasts need the iOS app"
          body="This version of the app can't read podcast feeds."
        />
      ) : shows.loading ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : shows.error ? (
        <Message title="The library couldn't be read" body={shows.error} />
      ) : (
        <FlatList<Show>
          data={shows.data ?? []}
          keyExtractor={(show) => show.id}
          contentContainerClassName="px-safe-or-4 pb-safe gap-1 grow"
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={refresh} />
          }
          ListHeaderComponent={
            refreshProblem ? (
              <Text className="text-destructive py-2 text-sm">
                {refreshProblem}
              </Text>
            ) : undefined
          }
          ListEmptyComponent={
            <Message
              title="No podcasts yet"
              body="Tap Add to search for a show or paste its RSS link."
            />
          }
          renderItem={({ item }) => (
            <Pressable
              className="active:bg-secondary flex-row items-center gap-3 rounded-md py-2"
              accessibilityRole="button"
              accessibilityLabel={
                item.author ? `${item.title}, ${item.author}` : item.title
              }
              onPress={() =>
                router.push({
                  pathname: "/podcasts/show/[id]",
                  params: { id: item.id },
                })
              }
            >
              <Artwork uri={item.imageUrl} size={56} />
              <View className="flex-1">
                <Text className="font-semibold" numberOfLines={2}>
                  {item.title}
                </Text>
                {item.author ? (
                  <Text
                    className="text-muted-foreground text-sm"
                    numberOfLines={1}
                  >
                    {item.author}
                  </Text>
                ) : null}
              </View>
            </Pressable>
          )}
        />
      )}
    </View>
  )
}

function Message({ title, body }: { title: string; body: string }) {
  return (
    <View className="items-center gap-2 px-8 py-12">
      <Text className="text-center font-semibold">{title}</Text>
      <Text className="text-muted-foreground text-center text-sm">{body}</Text>
    </View>
  )
}
