// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { announcedPercent, waitPercent } from "@/modules/podcasts/playWait"
import { type PlayWait, askToStream } from "@/modules/podcasts/playWaitStore"

import { useDownload } from "./useDownloads"

/**
 * In the mini player's place while "Skip ads" is on and the episode that was pressed is being
 * downloaded first: what is happening, how far it is and a way to stream it now. VoiceOver
 * hears the percent only every ten percent.
 */
export function DownloadWaitCard({ wait }: { wait: PlayWait }) {
  const percent = waitPercent(useDownload(wait.episodeId))
  const heard = announcedPercent(percent)
  return (
    <View className="flex-1 justify-center gap-1.5 px-4">
      <View className="flex-row items-center gap-3">
        <View className="flex-1" accessibilityLiveRegion="polite">
          <Text className="font-semibold" numberOfLines={1}>
            Downloading so ads can be skipped
          </Text>
          <Text
            className="text-muted-foreground text-sm"
            numberOfLines={1}
            accessibilityLabel={
              heard === null ? "Downloading" : `Downloading, ${heard} percent`
            }
          >
            {percent === null ? "Starting…" : `${percent}%`} · {wait.title}
          </Text>
        </View>
        <Pressable
          className="bg-secondary rounded-full px-3 py-1.5 active:opacity-60"
          accessibilityRole="button"
          accessibilityLabel="Stream now"
          onPress={askToStream}
        >
          <Text className="text-sm font-semibold">Stream now</Text>
        </Pressable>
      </View>
      <View
        className="bg-secondary h-1 overflow-hidden rounded-full"
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <View
          className="bg-primary h-1 rounded-full"
          style={{ width: `${percent ?? 0}%` }}
        />
      </View>
    </View>
  )
}
