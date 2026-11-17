// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Image } from "expo-image"
import { FileAudio, Podcast } from "lucide-react-native"
import { View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { cn } from "@/lib/utils"
import { LOCAL_ARTWORK } from "@/modules/podcasts/localFiles"

interface Props {
  uri: string | null
  size: number
  className?: string
}

/** A show's or episode's picture, or a plain tile with an icon when there is none. */
export function Artwork({ uri, size, className }: Props) {
  return (
    <View
      className={cn(
        "bg-secondary items-center justify-center overflow-hidden rounded-md",
        className,
      )}
      style={{ width: size, height: size }}
    >
      {uri === LOCAL_ARTWORK ? (
        // The "Your files" show has no picture to load: this tile is drawn here.
        <Icon as={FileAudio} size={size / 2.5} className="text-primary" />
      ) : uri ? (
        <Image
          source={{ uri }}
          style={{ width: size, height: size }}
          contentFit="cover"
          accessibilityIgnoresInvertColors
        />
      ) : (
        <Icon as={Podcast} size={size / 3} className="text-muted-foreground" />
      )}
    </View>
  )
}
