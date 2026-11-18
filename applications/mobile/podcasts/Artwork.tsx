// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Image } from "expo-image"
import { FileAudio, Podcast } from "lucide-react-native"
import { useMemo, useState } from "react"
import { PixelRatio, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { cn } from "@/lib/utils"
import { artworkSources, nextSource } from "@/modules/podcasts/artworkSource"
import { LOCAL_ARTWORK } from "@/modules/podcasts/localFiles"

/** The corner that suits a size: small for a row's thumbnail, larger as the picture grows. */
export function artworkRadius(size: number): string {
  return size <= 56 ? "rounded-lg" : size <= 140 ? "rounded-xl" : "rounded-2xl"
}

interface Props {
  uri: string | null
  size: number
  className?: string
}

/** A show's or episode's picture, or a plain tile with an icon when there is none. */
export function Artwork({ uri, size, className }: Props) {
  const scale = PixelRatio.get()
  const sources = useMemo(
    () => artworkSources(uri, size, scale),
    [uri, size, scale],
  )
  // The failed-address count belongs to one `uri`: a recycled list cell given another cover
  // starts again at that cover's first address.
  const [failure, setFailure] = useState({ uri, index: 0 })
  const index = failure.uri === uri ? failure.index : 0
  const source = sources[index]
  return (
    <View
      className={cn(
        "bg-secondary border-foreground/10 items-center justify-center overflow-hidden border",
        artworkRadius(size),
        className,
      )}
      style={{ width: size, height: size }}
    >
      {uri === LOCAL_ARTWORK ? (
        // The "Your files" show has no picture to load: this tile is drawn here.
        <Icon as={FileAudio} size={size / 2.5} className="text-primary" />
      ) : source ? (
        <Image
          source={{ uri: source }}
          recyclingKey={source}
          transition={150}
          onError={() => setFailure({ uri, index: nextSource(sources, index) })}
          style={{ width: "100%", height: "100%" }}
          contentFit="cover"
          accessibilityIgnoresInvertColors
        />
      ) : (
        <Icon as={Podcast} size={size / 3} className="text-muted-foreground" />
      )}
    </View>
  )
}
