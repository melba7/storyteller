// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Pressable, ScrollView } from "react-native"

import { Text } from "@/components/ui/text"

import { pick } from "./haptics"

export type PlayerPage = "now" | "notes" | "chapters" | "transcript"

const TITLES: Record<PlayerPage, string> = {
  now: "Now Playing",
  notes: "Notes",
  chapters: "Chapters",
  transcript: "Transcript",
}

/** The pages to offer: Chapters only when the episode has some. */
export function pagesFor(hasChapters: boolean): PlayerPage[] {
  return hasChapters
    ? ["now", "notes", "chapters", "transcript"]
    : ["now", "notes", "transcript"]
}

/** The page pills in a sideways scroll, so they fit at large text sizes. */
export function PagePills({
  pages,
  page,
  onChange,
}: {
  pages: readonly PlayerPage[]
  page: PlayerPage
  onChange: (page: PlayerPage) => void
}) {
  return (
    <ScrollView
      horizontal
      className="flex-1"
      contentContainerClassName="items-center gap-2 pr-2"
      showsHorizontalScrollIndicator={false}
      accessibilityRole="tablist"
    >
      {pages.map((name) => {
        const selected = name === page
        return (
          <Pressable
            key={name}
            className={`min-h-11 justify-center rounded-full px-4 ${
              selected ? "bg-white" : "bg-white/15 active:bg-white/25"
            }`}
            accessibilityRole="tab"
            accessibilityLabel={TITLES[name]}
            accessibilityState={{ selected }}
            onPress={() => {
              if (!selected) pick()
              onChange(name)
            }}
          >
            <Text
              className={`font-semibold ${selected ? "text-black" : "text-white"}`}
              numberOfLines={1}
            >
              {TITLES[name]}
            </Text>
          </Pressable>
        )
      })}
    </ScrollView>
  )
}

/** The episode's show notes, on their own page. */
export function NotesPage({ notes }: { notes: string }) {
  return (
    <ScrollView contentContainerClassName="px-safe-or-6 pb-safe gap-2 pb-8">
      <Text className="text-lg font-bold text-white">Show notes</Text>
      <Text selectable className="text-base leading-6 text-white/85">
        {notes === "" ? "No notes for this episode." : notes}
      </Text>
    </ScrollView>
  )
}
