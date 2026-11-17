import { skipToken } from "@reduxjs/toolkit/query"
import { Link } from "expo-router"
import { useEffect, useMemo, useState } from "react"
import {
  TouchableOpacity,
  View,
  type ViewStyle,
  useWindowDimensions,
} from "react-native"
import { Gesture, GestureDetector } from "react-native-gesture-handler"
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from "react-native-reanimated"
import { scheduleOnRN } from "react-native-worklets"

import { GlassCapsule } from "@/apple-look/GlassCapsule"
import { playerPositionSeeked } from "@/store/actions"
import { useAppDispatch, useAppSelector } from "@/store/appState"
import { useGetBookQuery } from "@/store/localApi"
import {
  formatTime,
  getCurrentTrackDuration,
  getCurrentlyPlayingBookUuid,
  getCurrentlyPlayingFormat,
  getFormattedDuration,
  getPlaybackRate,
  getPosition,
} from "@/store/selectors/bookshelfSelectors"
import { bookshelfSlice } from "@/store/slices/bookshelfSlice"

import { AudiobookCover } from "./AudiobookCover"
import { PlayPause } from "./PlayPause"
import { ProgressBar } from "./ProgressBar"
import { Text } from "./ui/text"

export function MiniPlayerWidget() {
  const progress = useAppSelector(getPosition)
  const startPosition = 0
  const endPosition = useAppSelector(getCurrentTrackDuration)
  const rate = useAppSelector(getPlaybackRate)
  const formattedDuration = useAppSelector(getFormattedDuration)

  const dimensions = useWindowDimensions()

  const dispatch = useAppDispatch()
  const [eagerProgress, setEagerProgress] = useState(progress)

  const formattedEagerProgress = useMemo(() => {
    return formatTime(eagerProgress, rate)
  }, [eagerProgress, rate])

  const formattedProgress = useMemo(() => {
    return `${formattedEagerProgress} / ${formattedDuration}`
  }, [formattedEagerProgress, formattedDuration])

  useEffect(() => {
    setEagerProgress(progress)
  }, [progress])

  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)
  const format = useAppSelector(getCurrentlyPlayingFormat)
  const { data: book } = useGetBookQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )

  function onPanEnd() {
    dispatch(bookshelfSlice.actions.miniPlayerWidgetSwiped())
    translateX.set(0)
  }

  const translateX = useSharedValue(0)

  const panGesture = Gesture.Pan()
    .onUpdate((event) => {
      "worklet"

      translateX.set(event.translationX)
    })
    .onEnd((event) => {
      "worklet"

      if (Math.abs(event.translationX) > dimensions.width * 0.25) {
        translateX.value = withTiming(
          dimensions.width * (event.translationX < 1 ? -2 : 2),
          {
            duration: 1200,
            easing: Easing.out(Easing.quad),
          },
        )
        scheduleOnRN(onPanEnd)
      } else {
        translateX.value = withTiming(0, {
          duration: 150,
          easing: Easing.out(Easing.quad),
        })
      }
    })

  const widgetAnimatedStyle = useAnimatedStyle((): ViewStyle => ({
    transform: [{ translateX: translateX.value }],
  }))

  if (format === "ebook") return null

  if (!bookUuid) return null

  return (
    <Animated.View
      className="mb-safe-offset-2 right-safe-or-3 left-safe-or-3 absolute bottom-0 z-90"
      style={widgetAnimatedStyle}
    >
      {book && (
        <GlassCapsule className="h-14">
          <GestureDetector gesture={panGesture}>
            <View className="h-14 flex-row items-center gap-2 pr-2">
              <Link
                href={{
                  pathname: "/listen/[uuid]",
                  params: { uuid: bookUuid, format },
                }}
                asChild
              >
                <TouchableOpacity
                  accessibilityLabel={`Open audio player for ${book.title}`}
                  accessibilityRole="button"
                  className="flex-1 flex-row items-center gap-3 pl-2"
                >
                  <View
                    className="border-foreground/10 h-10 w-10 overflow-hidden border"
                    style={{ borderRadius: 6 }}
                  >
                    <AudiobookCover book={book} />
                  </View>
                  <View className="flex-1">
                    <Text
                      numberOfLines={1}
                      className="text-[15px] font-semibold"
                    >
                      {book.title}
                    </Text>
                    <Text
                      numberOfLines={1}
                      className="text-muted-foreground text-[13px]"
                    >
                      {formattedProgress}
                    </Text>
                  </View>
                </TouchableOpacity>
              </Link>
              <PlayPause />
            </View>
          </GestureDetector>
          <View className="absolute right-6 bottom-0 left-6">
            <ProgressBar
              slim
              className="h-2"
              trackClassName="bg-foreground/10 h-[3px]"
              fillClassName="bg-foreground/50"
              accessibilityLabel="Mini player progress"
              start={startPosition}
              stop={endPosition}
              progress={eagerProgress}
              onProgressChange={(value) => {
                setEagerProgress(value)
                dispatch(playerPositionSeeked({ progress: value }))
              }}
            />
          </View>
        </GlassCapsule>
      )}
    </Animated.View>
  )
}
