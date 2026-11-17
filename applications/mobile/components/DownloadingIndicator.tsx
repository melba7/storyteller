import { ArrowDown, type LucideIcon } from "lucide-react-native"
import { useDeferredValue } from "react"
import { View, type ViewStyle } from "react-native"
import { AnimatedCircularProgress } from "react-native-circular-progress"
import { useCSSVariable } from "uniwind"

import { useColorTheme } from "@/hooks/useColorTheme"
import { cn } from "@/lib/utils"

import { Icon } from "./ui/icon"

type Props = {
  className?: string | undefined
  progress: number
  size: number
  style: ViewStyle
  icon?: LucideIcon
}

export function DownloadingIndicator({
  className,
  progress,
  size,
  style,
  icon: IconComponent = ArrowDown,
}: Props) {
  const { background } = useColorTheme()
  const primary = useCSSVariable("--color-primary") as string
  const deferredProgress = useDeferredValue(progress)

  return (
    <View
      className={cn("bg-background rounded-full p-[1px]", className)}
      style={[
        {
          width: size + 2,
          height: size + 2,
        },
        style,
      ]}
    >
      <AnimatedCircularProgress
        size={size}
        width={1}
        fill={deferredProgress}
        rotation={0}
        tintColor={primary}
        backgroundColor={background}
      >
        {() => <Icon as={IconComponent} size={size * 0.8} color={primary} />}
      </AnimatedCircularProgress>
    </View>
  )
}
