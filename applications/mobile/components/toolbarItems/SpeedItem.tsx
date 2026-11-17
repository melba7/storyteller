import { skipToken } from "@reduxjs/toolkit/query"
import { router } from "expo-router"
import { Gauge, MinusCircle, PlusCircle } from "lucide-react-native"

import { Group } from "@/components/ui/Group"
import { Stack } from "@/components/ui/Stack"
import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Slider } from "@/components/ui/slider"
import { Text } from "@/components/ui/text"
import { cn } from "@/lib/utils"
import { useAppSelector } from "@/store/appState"
import {
  useGetBookPreferencesQuery,
  useUpdateBookPreferenceMutation,
} from "@/store/localApi"
import {
  getCurrentlyPlayingBookUuid,
  getPlaybackRate,
} from "@/store/selectors/bookshelfSelectors"
import { type UUID } from "@/uuid"

const speedPresets = [
  0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3, 3.25, 3.5, 3.75, 4,
]

function roundSpeed(speed: number) {
  return Math.min(4, Math.max(0.5, Math.round(speed * 10) / 10))
}

function SpeedControl({
  label,
  value,
  onChange,
}: {
  label: string
  value: number
  onChange: (speed: number) => void
}) {
  return (
    <Stack className="w-full gap-3 px-1">
      <Group className="items-center justify-between">
        <Text>{label}</Text>
        <Text>{value}x</Text>
      </Group>
      <Group className="items-center gap-4">
        <Button
          accessibilityLabel={`Decrease ${label.toLowerCase()} speed`}
          variant="ghost"
          size="icon"
          className="rounded-full"
          onPress={() => {
            onChange(roundSpeed(value - 0.1))
          }}
        >
          <Icon as={MinusCircle} size={16} />
        </Button>
        <Slider
          accessibilityLabel={`${label} speed`}
          className="grow"
          value={value}
          step={0.1}
          start={0.5}
          stop={4}
          onValueChange={(newValue) => {
            onChange(roundSpeed(newValue ?? 1))
          }}
        />
        <Button
          accessibilityLabel={`Increase ${label.toLowerCase()} speed`}
          variant="ghost"
          size="icon"
          className="rounded-full"
          onPress={() => {
            onChange(roundSpeed(value + 0.1))
          }}
        >
          <Icon as={PlusCircle} size={16} />
        </Button>
      </Group>
      <Group className="flex-wrap gap-2">
        {speedPresets.map((speed) => (
          <Button
            accessibilityLabel={`Set ${label.toLowerCase()} speed to ${speed}x`}
            className="h-8 min-w-10 rounded-full px-2"
            variant="secondary"
            key={speed}
            onPress={() => {
              onChange(speed)
            }}
          >
            <Text maxFontSizeMultiplier={1.5} className="text-[10px]">
              {speed}
            </Text>
          </Button>
        ))}
      </Group>
    </Stack>
  )
}

export function SpeedMenuContent({
  bookUuid,
}: {
  bookUuid?: UUID | undefined
}) {
  const { data: bookPreferences } = useGetBookPreferencesQuery(
    bookUuid
      ? {
          uuid: bookUuid,
        }
      : skipToken,
  )
  const listeningSpeed = bookPreferences?.audio?.speed ?? 1
  const readaloudSpeed =
    bookPreferences?.audio?.readaloudSpeed ?? listeningSpeed

  const [updateBookPreference] = useUpdateBookPreferenceMutation()

  if (!bookUuid) return null

  return (
    <Stack className="items-center gap-5 p-5">
      <Group className="w-full items-center justify-between">
        <Text>Playback speed</Text>
      </Group>
      <SpeedControl
        label="Listening"
        value={listeningSpeed}
        onChange={(speed) => {
          updateBookPreference({
            bookUuid,
            name: "audio",
            value: {
              ...bookPreferences?.audio,
              speed,
            },
          })
        }}
      />
      <SpeedControl
        label="Readaloud"
        value={readaloudSpeed}
        onChange={(readaloudSpeed) => {
          updateBookPreference({
            bookUuid,
            name: "audio",
            value: {
              ...bookPreferences?.audio,
              readaloudSpeed,
            },
          })
        }}
      />
    </Stack>
  )
}

type Props = {
  /** Colour class for the icon and the speed label. */
  iconClassName?: string
}

export function SpeedItem({ iconClassName = "text-foreground" }: Props) {
  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)
  const currentSpeed = useAppSelector(getPlaybackRate)

  if (!bookUuid) return null

  return (
    <Button
      accessibilityLabel={`Playback speed, ${currentSpeed}x`}
      variant="ghost"
      size="icon"
      className="h-10 w-12 rounded-full px-0 sm:h-10 sm:w-12"
      onPress={() => {
        router.push({
          pathname: "/speed-menu",
          params: { uuid: bookUuid },
        })
      }}
    >
      {currentSpeed === 1 ? (
        <Icon as={Gauge} size={24} className={iconClassName} />
      ) : (
        <Text
          numberOfLines={1}
          minimumFontScale={1}
          maxFontSizeMultiplier={1}
          className={cn("text-[13px] font-semibold", iconClassName)}
        >
          {currentSpeed}×
        </Text>
      )}
    </Button>
  )
}
