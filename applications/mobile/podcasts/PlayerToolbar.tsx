// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Ellipsis } from "lucide-react-native"
import { useState } from "react"
import { ActionSheetIOS, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import { speedLabel } from "@/modules/podcasts/playbackRules"
import { player, usePlayer } from "@/modules/podcasts/playerInstance"
import { isPreviewId } from "@/modules/podcasts/preview"
import { placeShare } from "@/modules/podcasts/share"

import { AirPlayButton } from "./AirPlayButton"
import { BookmarkButton } from "./LibraryButtons"
import { shareContent } from "./ShareButton"
import { SleepTimerButton } from "./SleepTimerSheet"
import { SpeedSheet } from "./SpeedPanel"
import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { useEpisode } from "./hooks"

/** One of the toolbar's five even slots, 44 pt high. */
function Slot({ children }: { children?: React.ReactNode }) {
  return (
    <View className="h-11 flex-1 items-center justify-center">{children}</View>
  )
}

/**
 * The player's toolbar: speed, sleep timer, AirPlay, bookmark and "…" in five even slots.
 * "…" holds star, add to a playlist and share this place.
 */
export function PlayerToolbar() {
  const view = usePlayer()
  const [showSpeed, setShowSpeed] = useState(false)
  const id = view.episode?.id ?? ""
  const preview = isPreviewId(id)
  const starredAt = useEpisode(id).data?.starredAt ?? null

  function openMenu() {
    const starred = starredAt !== null
    const items: { title: string; run: () => void }[] = []
    if (id !== "" && !preview) {
      items.push({
        title: starred ? "Unstar this episode" : "Star this episode",
        run: () => {
          setStarred([id], !starred).catch((cause: unknown) =>
            console.warn("Couldn't change the episode's star", cause),
          )
        },
      })
    }
    items.push(
      {
        title: "Add to playlist",
        run: () => {
          const { episode, show } = player.getView()
          if (episode) void chooseAndAddToPlaylist(episode, show)
        },
      },
      {
        title: "Share this place",
        run: () =>
          void shareContent(() => {
            const { episode, show, position } = player.getView()
            return episode ? placeShare(episode, show, position) : null
          }),
      },
    )
    ActionSheetIOS.showActionSheetWithOptions(
      {
        options: [...items.map((item) => item.title), "Cancel"],
        cancelButtonIndex: items.length,
      },
      (index) => items[index]?.run(),
    )
  }

  return (
    <View className="w-full flex-row items-center">
      <Slot>
        <Pressable
          className="h-11 min-w-11 items-center justify-center rounded-full px-2 active:bg-white/15"
          accessibilityRole="button"
          accessibilityLabel={`Playback speed ${speedLabel(view.rate)}`}
          onPress={() => setShowSpeed(true)}
        >
          <Text
            className="text-sm font-semibold text-white"
            style={{ fontVariant: ["tabular-nums"] }}
            numberOfLines={1}
          >
            {speedLabel(view.rate).replace("x", "×")}
          </Text>
        </Pressable>
      </Slot>
      <Slot>
        <SleepTimerButton />
      </Slot>
      <Slot>
        <AirPlayButton />
      </Slot>
      <Slot>{preview ? null : <BookmarkButton />}</Slot>
      <Slot>
        {view.episode ? (
          <Pressable
            className="size-11 items-center justify-center rounded-full active:bg-white/15"
            accessibilityRole="button"
            accessibilityLabel="More: star, add to a playlist, share this place"
            onPress={openMenu}
          >
            <Icon as={Ellipsis} size={22} className="text-white" />
          </Pressable>
        ) : null}
      </Slot>
      <SpeedSheet
        visible={showSpeed}
        onClose={() => setShowSpeed(false)}
        rate={view.rate}
        onChange={(rate) => void player.setRate(rate)}
      />
    </View>
  )
}
