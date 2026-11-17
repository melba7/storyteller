// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ActivityIndicator, View } from "react-native"

import { Text } from "@/components/ui/text"

import { ManualPlaylist } from "./ManualPlaylist"
import { PlaylistScreen } from "./PlaylistScreen"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { usePlaylist } from "./usePlaylists"

/** A playlist's page: its rules and episodes if it is smart, its own list if it is by hand. */
export function PlaylistPage({ id }: { id: string }) {
  const playlist = usePlaylist(id)
  if (playlist.data?.kind === "manual") {
    return <ManualPlaylist playlist={playlist.data} />
  }
  if (playlist.data) return <PlaylistScreen id={id} />
  return (
    <View className="bg-background flex-1">
      <ScreenBar title="Playlist" />
      {playlist.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : (
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            {playlist.error ?? "This playlist isn't there."}
          </Text>
        </BelowBar>
      )}
    </View>
  )
}
