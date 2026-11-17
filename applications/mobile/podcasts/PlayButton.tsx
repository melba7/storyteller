// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator, Pressable } from "react-native"
import { useCSSVariable } from "uniwind"

import { Icon } from "@/components/ui/icon"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { player, usePlayerValue } from "@/modules/podcasts/playerInstance"

/** What an episode's play button shows. */
type Status = "idle" | "playing" | "buffering"

/** Plays, pauses or resumes one episode. Draws again only when this episode's status changes. */
export function useEpisodeStatus(episodeId: string): Status {
  return usePlayerValue((view): Status => {
    if (view.episode?.id !== episodeId) return "idle"
    if (view.isBuffering) return "buffering"
    return view.isPlaying ? "playing" : "idle"
  })
}

export function pressEpisode(
  episode: StoredEpisode,
  show: Show | null,
  status: Status,
) {
  if (status === "playing") void player.togglePlayPause()
  else void player.playEpisode(episode, show)
}

interface Props {
  episode: StoredEpisode
  show: Show | null
  size?: number
}

/** The round play or pause button on an episode row. */
export function PlayButton({ episode, show, size = 44 }: Props) {
  const status = useEpisodeStatus(episode.id)
  const onPrimary = useCSSVariable("--color-primary-foreground") as string
  return (
    <Pressable
      className="bg-primary items-center justify-center rounded-full active:opacity-80"
      style={{ width: size, height: size }}
      accessibilityRole="button"
      accessibilityLabel={
        status === "playing"
          ? `Pause ${episode.title}`
          : `Play ${episode.title}`
      }
      onPress={() => pressEpisode(episode, show, status)}
    >
      {status === "buffering" ? (
        <ActivityIndicator color={onPrimary} accessibilityLabel="Buffering" />
      ) : (
        <Icon
          as={status === "playing" ? Pause : Play}
          size={size / 2}
          className="text-primary-foreground"
          fill={onPrimary}
        />
      )}
    </Pressable>
  )
}
