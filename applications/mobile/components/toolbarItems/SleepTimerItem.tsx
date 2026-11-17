import { intervalToDuration, isFuture, isPast } from "date-fns"
import { ClockFading } from "lucide-react-native"
import { useEffect, useState } from "react"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu, type MenuAction } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import { useIsNotBackground } from "@/hooks/useIsNotBackground"
import { cn } from "@/lib/utils"
import { useAppDispatch, useAppSelector } from "@/store/appState"
import { getSleepTimer } from "@/store/selectors/sleepTimerSelectors"
import { sleepTimerSlice } from "@/store/slices/sleepTimerSlice"

function formatSleepTimer(sleepTimer: Date) {
  const duration = intervalToDuration({
    start: new Date(),
    end: sleepTimer,
  })
  const minutes = String(
    (duration.minutes ?? 0) + (duration.hours ? duration.hours * 60 : 0),
  ).padStart(2, "0")
  const seconds = String(duration.seconds ?? 0).padStart(2, "0")
  return `${minutes}:${seconds}`
}

const MAX_FONT_SCALE = 1.75

type Props = {
  /** Colour class for the icon and the countdown. */
  iconClassName?: string
}

export function SleepTimerItem({ iconClassName = "text-foreground" }: Props) {
  const dispatch = useAppDispatch()
  const sleepTimer = useAppSelector(getSleepTimer)
  const isNotBackground = useIsNotBackground()

  const [formattedSleepTimer, setFormattedSleepTimer] = useState<string | null>(
    sleepTimer && isFuture(sleepTimer) ? formatSleepTimer(sleepTimer) : null,
  )

  const startSleepTimer = (duration: number) => {
    dispatch(
      sleepTimerSlice.actions.started({
        deadline: Date.now() + duration,
        duration,
      }),
    )
  }

  useEffect(() => {
    if (!isNotBackground) return

    if (sleepTimer) {
      setFormattedSleepTimer(
        isFuture(sleepTimer) ? formatSleepTimer(sleepTimer) : null,
      )
      const intervalId = setInterval(() => {
        if (isPast(sleepTimer)) {
          clearInterval(intervalId)
          setFormattedSleepTimer(null)
          return
        }
        setFormattedSleepTimer(formatSleepTimer(sleepTimer))
      }, 500)
      return () => clearInterval(intervalId)
    } else {
      setFormattedSleepTimer(null)
    }
    return () => {}
  }, [isNotBackground, sleepTimer])

  const menuActions: MenuAction[] = [
    {
      id: "off",
      title: "Off",
      onPress: () => {
        dispatch(sleepTimerSlice.actions.cancelled())
      },
    },
    ...[5, 10, 15, 30, 45, 60, 90, 120].map((minutes) => ({
      id: `${minutes}-min`,
      title: `${minutes} min`,
      onPress: () => {
        startSleepTimer(minutes * 60 * 1000)
      },
    })),
    ...(__DEV__
      ? [
          {
            id: "5-sec",
            title: "5 sec",
            onPress: () => {
              startSleepTimer(5 * 1000)
            },
          },
          {
            id: "30-sec",
            title: "30 sec",
            onPress: () => {
              startSleepTimer(30 * 1000)
            },
          },
        ]
      : []),
  ]

  return (
    <Menu actions={menuActions}>
      <Button
        accessibilityLabel={
          formattedSleepTimer
            ? `Sleep timer, ${formattedSleepTimer} remaining`
            : "Open sleep timer menu"
        }
        variant="ghost"
        size="icon"
        className="h-10 w-12 rounded-full px-0 sm:h-10 sm:w-12"
      >
        {formattedSleepTimer ? (
          <Text
            numberOfLines={1}
            minimumFontScale={1}
            maxFontSizeMultiplier={MAX_FONT_SCALE}
            className={cn("text-[13px] font-semibold", iconClassName)}
          >
            {formattedSleepTimer}
          </Text>
        ) : (
          <Icon as={ClockFading} size={24} className={iconClassName} />
        )}
      </Button>
    </Menu>
  )
}
