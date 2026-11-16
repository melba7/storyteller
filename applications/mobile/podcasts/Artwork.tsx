// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Image } from "expo-image"
import { Podcast } from "lucide-react-native"
import { View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { cn } from "@/lib/utils"

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
      {uri ? (
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
