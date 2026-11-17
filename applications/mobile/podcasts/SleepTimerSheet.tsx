// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Moon } from "lucide-react-native"
import { useState } from "react"
import { Modal, Pressable, TextInput, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { usePlayer } from "@/modules/podcasts/playerInstance"
import {
  SLEEP_EXTRA_MINUTES,
  SLEEP_PRESET_MINUTES,
  minutesLabel,
  parseCustomMinutes,
  sleepButtonLabel,
  sleepButtonText,
  sleepSecondsLeft,
} from "@/modules/podcasts/sleepTimer"

import { useChapters } from "./useChapters"
import { sleepTimer, useNow, useSleepTimer } from "./useSleepTimer"

/** The moon slot in the player's toolbar: opens the sleep timer choices and shows the time left in its place. */
export function SleepTimerButton() {
  const state = useSleepTimer()
  const view = usePlayer()
  const chapters = useChapters(view.episode?.id ?? "")
  const [open, setOpen] = useState(false)
  const now = useNow(state.kind === "countdown")
  const left = sleepSecondsLeft(
    state,
    now,
    view.position,
    view.duration,
    view.rate,
  )
  const text = sleepButtonText(left, state)

  return (
    <>
      <Pressable
        className="h-11 min-w-11 items-center justify-center rounded-full px-2 active:bg-white/15"
        accessibilityRole="button"
        accessibilityLabel={sleepButtonLabel(left, state)}
        onPress={() => setOpen(true)}
      >
        {text === "" ? (
          <Icon as={Moon} size={22} className="text-white" />
        ) : (
          <Text
            className="text-sm font-semibold text-white"
            style={{ fontVariant: ["tabular-nums"] }}
            numberOfLines={1}
          >
            {text}
          </Text>
        )}
      </Pressable>
      <Modal
        visible={open}
        transparent
        animationType="slide"
        onRequestClose={() => setOpen(false)}
      >
        <SleepSheet
          running={state.kind !== "none"}
          counting={state.kind === "countdown"}
          hasChapters={chapters.length > 0}
          onClose={() => setOpen(false)}
        />
      </Modal>
    </>
  )
}

function SleepSheet({
  running,
  counting,
  hasChapters,
  onClose,
}: {
  running: boolean
  counting: boolean
  hasChapters: boolean
  onClose: () => void
}) {
  const [typed, setTyped] = useState("")
  const custom = parseCustomMinutes(typed)

  function choose(action: () => void) {
    action()
    onClose()
  }

  return (
    <View className="flex-1 justify-end">
      <Pressable
        className="absolute inset-0 bg-black/50"
        accessibilityRole="button"
        accessibilityLabel="Close the sleep timer"
        onPress={onClose}
      />
      <View className="bg-background pb-safe-offset-3 gap-1 rounded-t-3xl px-6 pt-5">
        <Text className="pb-2 text-lg font-semibold">Sleep timer</Text>
        {SLEEP_PRESET_MINUTES.map((minutes) => (
          <Choice
            key={minutes}
            label={minutesLabel(minutes)}
            onPress={() => choose(() => sleepTimer.startMinutes(minutes))}
          />
        ))}
        {hasChapters ? (
          <Choice
            label="End of chapter"
            onPress={() => choose(sleepTimer.endOfChapter)}
          />
        ) : null}
        <Choice
          label="End of episode"
          onPress={() => choose(sleepTimer.endOfEpisode)}
        />
        <View className="flex-row items-center gap-3 py-2">
          <TextInput
            className="border-border text-foreground h-11 flex-1 rounded-xl border px-3"
            placeholder="Your own time, in minutes"
            keyboardType="number-pad"
            value={typed}
            onChangeText={setTyped}
            maxLength={4}
            accessibilityLabel="Your own time in minutes, 1 to 720"
          />
          <Pressable
            className={`h-11 justify-center rounded-xl px-5 ${
              custom === null ? "bg-secondary" : "bg-primary"
            }`}
            accessibilityRole="button"
            accessibilityLabel="Start with your own time"
            accessibilityState={{ disabled: custom === null }}
            disabled={custom === null}
            onPress={() =>
              custom !== null && choose(() => sleepTimer.startMinutes(custom))
            }
          >
            <Text
              className={
                custom === null
                  ? "text-muted-foreground"
                  : "text-primary-foreground"
              }
            >
              Start
            </Text>
          </Pressable>
        </View>
        {counting ? (
          <Choice
            label={`Add ${SLEEP_EXTRA_MINUTES} minutes`}
            onPress={() => choose(sleepTimer.addFiveMinutes)}
          />
        ) : null}
        {running ? (
          <Choice
            label="Turn off the timer"
            destructive
            onPress={() => choose(sleepTimer.cancel)}
          />
        ) : null}
      </View>
    </View>
  )
}

function Choice({
  label,
  onPress,
  destructive = false,
}: {
  label: string
  onPress: () => void
  destructive?: boolean
}) {
  return (
    <Pressable
      className="border-border active:bg-secondary min-h-11 justify-center border-b"
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Text className={destructive ? "text-destructive" : ""}>{label}</Text>
    </Pressable>
  )
}
