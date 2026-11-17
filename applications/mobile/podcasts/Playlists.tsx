// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { ChevronRight, Plus } from "lucide-react-native"
import { ActivityIndicator, FlatList, Pressable, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { describeRules } from "@/modules/podcasts/playlistRules"
import { type Playlist } from "@/modules/podcasts/playlists"

import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { usePlaylists, useSmartEpisodes } from "./usePlaylists"

/** The Playlists tab: the smart playlists, each with how many episodes it holds now. */
export function Playlists() {
  const router = useRouter()
  const playlists = usePlaylists()
  return (
    <View className="pt-safe bg-background flex-1">
      <StatusBar verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        title="Playlists"
        left={<SectionMenuButton current="podcasts" />}
        right={
          <Button
            variant="ghost"
            size="icon"
            accessibilityLabel="New playlist"
            onPress={() =>
              router.push({
                pathname: "/podcasts/(tabs)/(playlists)/playlist-edit/[id]",
                params: { id: "new" },
              })
            }
          >
            <Icon as={Plus} size={22} className="text-primary" />
          </Button>
        }
      />
      {playlists.loading ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : (
        <FlatList<Playlist>
          data={playlists.data ?? []}
          keyExtractor={(playlist) => playlist.id}
          contentContainerClassName="px-safe-or-4"
          contentInsetAdjustmentBehavior="automatic"
          ListEmptyComponent={
            <Text className="text-muted-foreground px-4 py-12 text-center">
              {playlists.error ??
                "No playlists. Tap + to make one from rules you choose."}
            </Text>
          }
          renderItem={({ item }) => <PlaylistRow playlist={item} />}
        />
      )}
    </View>
  )
}

function PlaylistRow({ playlist }: { playlist: Playlist }) {
  const router = useRouter()
  const count = useSmartEpisodes(playlist).data?.length
  const summary = describeRules(playlist.rules)
  const label =
    count === undefined ? "" : count === 1 ? "1 episode" : `${count} episodes`
  return (
    <Pressable
      className="border-border active:bg-secondary flex-row items-center gap-3 border-b py-4"
      accessibilityRole="button"
      accessibilityLabel={`${playlist.title}, ${label}. ${summary}`}
      onPress={() =>
        router.push({
          pathname: "/podcasts/(tabs)/(playlists)/playlist/[id]",
          params: { id: playlist.id },
        })
      }
    >
      <View className="flex-1 gap-1">
        <Text className="font-semibold">{playlist.title}</Text>
        <Text className="text-muted-foreground text-sm" numberOfLines={2}>
          {[label, summary].filter((part) => part !== "").join(" · ")}
        </Text>
      </View>
      <Icon as={ChevronRight} size={20} className="text-muted-foreground" />
    </Pressable>
  )
}
