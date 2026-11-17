// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { cn } from "@/lib/utils"
import { THEMES, type ThemeMode } from "@/modules/podcasts/theme"

import { usePodcastsTheme } from "./usePodcastsTheme"

const MODES: { mode: ThemeMode; label: string; note: string }[] = [
  {
    mode: "app",
    label: "Like the app",
    note: "Podcasts look light or dark the way the rest of the app does.",
  },
  {
    mode: "theme",
    label: "One theme",
    note: "Podcasts always use this theme.",
  },
  {
    mode: "ios",
    label: "Follow iOS",
    note: "Pick one theme for when iOS is light and one for when it is dark.",
  },
]

/** One theme as a small picture of its colours with its name under it. */
function Swatch({
  id,
  selected,
  onPress,
}: {
  id: string
  selected: boolean
  onPress: () => void
}) {
  const theme = THEMES.find((each) => each.id === id)
  if (!theme) return null
  return (
    <Pressable
      className="w-20 items-center gap-1"
      accessibilityRole="button"
      accessibilityLabel={`${theme.name} theme`}
      accessibilityState={{ selected }}
      onPress={onPress}
    >
      <View
        className={cn(
          "h-14 w-14 items-center justify-center rounded-2xl border-2",
          selected ? "border-primary" : "border-border",
        )}
        style={{ backgroundColor: theme.swatch.background }}
      >
        <View
          className="h-5 w-5 rounded-full"
          style={{ backgroundColor: theme.swatch.accent }}
        />
      </View>
      <Text
        className={cn(
          "text-xs",
          selected ? "font-semibold" : "text-muted-foreground",
        )}
        numberOfLines={1}
      >
        {theme.name}
      </Text>
    </Pressable>
  )
}

function SwatchRow({
  dark,
  selected,
  onPick,
}: {
  /** Only the dark or only the light themes; null for all of them. */
  dark: boolean | null
  selected: string
  onPick: (id: string) => void
}) {
  return (
    <View className="flex-row flex-wrap gap-y-3">
      {THEMES.filter((theme) => dark === null || theme.dark === dark).map(
        (theme) => (
          <Swatch
            key={theme.id}
            id={theme.id}
            selected={theme.id === selected}
            onPress={() => onPick(theme.id)}
          />
        ),
      )}
    </View>
  )
}

/** Profile's Appearance section: how the Podcasts section looks. */
export function AppearanceSection() {
  const { choice, setChoice } = usePodcastsTheme()
  const current = MODES.find((each) => each.mode === choice.mode) ?? MODES[0]!
  return (
    <View className="border-border gap-3 border-b py-4">
      <Text className="font-semibold">Appearance</Text>
      <View className="bg-secondary flex-row rounded-lg p-1">
        {MODES.map(({ mode, label }) => (
          <Pressable
            key={mode}
            className={cn(
              "flex-1 items-center rounded-md py-2",
              choice.mode === mode && "bg-background",
            )}
            accessibilityRole="button"
            accessibilityLabel={label}
            accessibilityState={{ selected: choice.mode === mode }}
            onPress={() => setChoice({ mode })}
          >
            <Text className="text-sm font-medium">{label}</Text>
          </Pressable>
        ))}
      </View>
      <Text className="text-muted-foreground text-sm">{current.note}</Text>
      {choice.mode === "theme" ? (
        <SwatchRow
          dark={null}
          selected={choice.theme}
          onPick={(theme) => setChoice({ theme })}
        />
      ) : null}
      {choice.mode === "ios" ? (
        <>
          <Text className="text-sm font-medium">When iOS is light</Text>
          <SwatchRow
            dark={false}
            selected={choice.lightTheme}
            onPick={(lightTheme) => setChoice({ lightTheme })}
          />
          <Text className="text-sm font-medium">When iOS is dark</Text>
          <SwatchRow
            dark
            selected={choice.darkTheme}
            onPick={(darkTheme) => setChoice({ darkTheme })}
          />
        </>
      ) : null}
    </View>
  )
}
