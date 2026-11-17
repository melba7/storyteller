// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"
import Svg, { Circle } from "react-native-svg"
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

const RING_WIDTH = 3
const RING_GAP = 2

/** A ring around the button: a faint track and the listened part on top, from the top. */
export function ProgressRing({
  fraction,
  size,
  color,
}: {
  fraction: number
  size: number
  color: string
}) {
  const radius = (size - RING_WIDTH) / 2
  const circumference = 2 * Math.PI * radius
  const common = {
    cx: size / 2,
    cy: size / 2,
    r: radius,
    strokeWidth: RING_WIDTH,
    fill: "none",
  }
  return (
    <Svg
      width={size}
      height={size}
      style={{ position: "absolute" }}
      pointerEvents="none"
    >
      <Circle {...common} stroke={color} strokeOpacity={0.2} />
      {fraction > 0 ? (
        <Circle
          {...common}
          stroke={color}
          strokeLinecap="round"
          strokeDasharray={`${circumference} ${circumference}`}
          strokeDashoffset={circumference * (1 - fraction)}
          rotation={-90}
          origin={`${size / 2}, ${size / 2}`}
        />
      ) : null}
    </Svg>
  )
}

interface Props {
  episode: StoredEpisode
  show: Show | null
  size?: number
  /** The listened share (0 to 1) to draw as a ring; null draws no ring. */
  ring?: number | null
}

/**
 * The round play or pause button on an episode row, with a progress ring when asked. The
 * face is 36 pt and its `hitSlop` keeps the touch target at 44 pt.
 */
export function PlayButton({ episode, show, size = 36, ring = null }: Props) {
  const status = useEpisodeStatus(episode.id)
  const onPrimary = useCSSVariable("--color-primary-foreground") as string
  const primary = useCSSVariable("--color-primary") as string
  // The room for the ring is kept even when there is none, so rows line up.
  const outer = size + 2 * (RING_WIDTH + RING_GAP)
  return (
    <View
      className="items-center justify-center"
      style={{ width: outer, height: outer }}
    >
      {ring === null ? null : (
        <ProgressRing fraction={ring} size={outer} color={primary} />
      )}
      <ButtonFace
        episode={episode}
        show={show}
        size={size}
        status={status}
        onPrimary={onPrimary}
        primary={primary}
      />
    </View>
  )
}

function ButtonFace({
  episode,
  show,
  size,
  status,
  onPrimary,
  primary,
}: {
  episode: StoredEpisode
  show: Show | null
  size: number
  status: Status
  onPrimary: string
  primary: string
}) {
  const filled = status !== "idle"
  const glyph = filled ? onPrimary : primary
  return (
    <Pressable
      className={`items-center justify-center rounded-full active:opacity-80 ${filled ? "bg-primary" : "bg-primary/15"}`}
      style={{ width: size, height: size }}
      hitSlop={Math.max(0, (44 - size) / 2)}
      accessibilityRole="button"
      accessibilityLabel={
        status === "playing"
          ? `Pause ${episode.title}`
          : `Play ${episode.title}`
      }
      onPress={() => pressEpisode(episode, show, status)}
    >
      {status === "buffering" ? (
        <ActivityIndicator color={glyph} accessibilityLabel="Buffering" />
      ) : (
        <Icon
          as={status === "playing" ? Pause : Play}
          size={size / 2}
          className={filled ? "text-primary-foreground" : "text-primary"}
          fill={glyph}
        />
      )}
    </Pressable>
  )
}
