// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Volume1, Volume2 } from "lucide-react-native"
import { View } from "react-native"

import { Text } from "@/components/ui/text"
import { adMarks, adRows } from "@/modules/podcasts/ads"
import type { PodcastChapter } from "@/modules/podcasts/index"
import { player, type usePlayer } from "@/modules/podcasts/playerInstance"
import {
  dateWords,
  isLightSheet,
  titleFade,
} from "@/modules/podcasts/playerSheet"
import { VolumeView } from "@/modules/podcasts/volumeView"

import { AdFindingLine } from "./AdFindingLine"
import { ChapterTitle } from "./ChapterBar"
import { MissedAdNote } from "./MissedAdNote"
import { PlayerMenu } from "./PlayerMenu"
import { type PlayerPanel } from "./PlayerPages"
import { PlayerTransport } from "./PlayerTransport"
import { SFIcon } from "./SFIcon"
import { SeekBar } from "./SeekBar"
import { SkippedAdNote } from "./SkippedAdNote"
import { useSheet } from "./playerSheetContext"
import { useAdsFile } from "./useAds"

/**
 * Everything under the artwork: the date, the title (fading out at the right) with its "..."
 * menu, the show, the scrubber with the chapter between its times, the transport row and the
 * volume slider.
 */
export function PlayerNowPlaying({
  view,
  chapters,
  onPanel,
  onShow,
  left,
  right,
}: {
  view: ReturnType<typeof usePlayer>
  chapters: readonly PodcastChapter[]
  onPanel: (panel: PlayerPanel) => void
  /** Go to the show and close the player. */
  onShow: () => void
  /** The space left and right of the controls, clear of the safe-area insets. */
  left: number
  right: number
}) {
  const sheet = useSheet()
  const { episode, show } = view
  const adsFile = useAdsFile(episode?.id ?? "")
  const marks = adsFile ? adMarks(adRows(adsFile), view.duration) : []
  if (!episode) return null
  const date = dateWords(episode.publishedAt)

  return (
    <View
      className="w-full gap-3 pt-3"
      style={{ paddingLeft: left, paddingRight: right }}
    >
      <View>
        {date === "" ? null : (
          <Text
            className="text-base font-medium"
            style={{ color: sheet.tint }}
            numberOfLines={1}
          >
            {date}
          </Text>
        )}
        <View className="flex-row items-center">
          <View className="flex-1 overflow-hidden">
            <Text
              className="text-xl font-bold"
              style={{ color: sheet.ink }}
              numberOfLines={1}
              ellipsizeMode="clip"
              accessibilityRole="header"
            >
              {episode.title}
            </Text>
            <View
              pointerEvents="none"
              className="absolute inset-y-0 right-0 w-8"
              style={{ backgroundImage: titleFade(sheet.mid) }}
            />
          </View>
          <PlayerMenu onPanel={onPanel} />
        </View>
        {show ? (
          <Text
            className="text-xl active:opacity-60"
            style={{ color: sheet.tint }}
            numberOfLines={1}
            accessibilityRole="button"
            accessibilityLabel={`Go to the show ${show.title}`}
            onPress={onShow}
          >
            {show.title}
          </Text>
        ) : null}
      </View>

      {view.error ? (
        <Text
          className="text-center text-sm font-semibold"
          style={{ color: sheet.ink }}
          accessibilityRole="alert"
        >
          {view.error}
        </Text>
      ) : null}

      <View>
        <SeekBar
          position={view.position}
          duration={view.duration}
          onSeek={(seconds) => void player.seekTo(seconds)}
          marks={marks}
          center={
            <ChapterTitle
              chapters={chapters}
              position={view.position}
              onOpen={() => onPanel("chapters")}
            />
          }
        />
      </View>
      <AdFindingLine episode={episode} show={show} />
      <SkippedAdNote />
      <MissedAdNote />

      <PlayerTransport view={view} />

      {VolumeView === null ? null : (
        <View className="flex-row items-center gap-3">
          <SFIcon
            name="speaker.fill"
            size={16}
            color={sheet.muted}
            fallback={Volume1}
          />
          <VolumeView
            light={isLightSheet(sheet.top)}
            fill={sheet.fill}
            track={sheet.rest}
            label="Volume"
            style={{ flex: 1, height: 40 }}
          />
          <SFIcon
            name="speaker.wave.3.fill"
            size={16}
            color={sheet.muted}
            fallback={Volume2}
          />
        </View>
      )}
    </View>
  )
}
