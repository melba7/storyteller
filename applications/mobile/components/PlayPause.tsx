import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator } from "react-native"
import { useCSSVariable } from "uniwind"

import { cn } from "@/lib/utils"
import { Storyteller } from "@/modules/readium"
import { useAppSelector } from "@/store/appState"
import {
  getIsAudioLoading,
  getIsPlaying,
} from "@/store/selectors/bookshelfSelectors"

import { Button, type ButtonProps } from "./ui/button"
import { Icon } from "./ui/icon"

type Props = {
  size?: number | undefined
  automaticRewind?: boolean
  buttonSize?: ButtonProps["size"]
  /** Colour class for the icon, for example "text-white" over the player's wash. */
  iconClassName?: string
}

export function PlayPause({
  size = 24,
  automaticRewind = true,
  buttonSize = "icon",
  iconClassName = "text-foreground",
}: Props) {
  const isPlaying = useAppSelector(getIsPlaying)
  const isLoading = useAppSelector(getIsAudioLoading)
  const spinnerColor = useCSSVariable(
    iconClassName === "text-white"
      ? "--color-primary-foreground"
      : "--color-foreground",
  ) as string
  // A big icon needs a bigger touch target than the button's standard one.
  const buttonStyle = size > 40 ? { height: size, width: size } : undefined

  if (isLoading) {
    return (
      <ActivityIndicator
        accessibilityLabel="Loading audio"
        accessibilityRole="progressbar"
        size={size}
        color={spinnerColor}
      />
    )
  }

  return isPlaying ? (
    <Button
      accessibilityLabel="Pause"
      variant="ghost"
      size={buttonSize}
      style={buttonStyle}
      onPress={() => {
        Storyteller.pause()
      }}
    >
      <Icon
        as={Pause}
        fill="currentColor"
        className={iconClassName}
        size={size}
      />
    </Button>
  ) : (
    <Button
      accessibilityLabel="Play"
      variant="ghost"
      size={buttonSize}
      style={buttonStyle}
      onPress={() => {
        Storyteller.play(automaticRewind)
      }}
    >
      <Icon
        as={Play}
        fill="currentColor"
        className={cn("bg-transparent", iconClassName)}
        size={size}
      />
    </Button>
  )
}
