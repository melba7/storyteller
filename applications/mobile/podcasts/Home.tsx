// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { ChevronRight } from "lucide-react-native"
import { type ReactNode } from "react"
import { Pressable, ScrollView, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  NEW_HREF,
  showHref,
  showsHref,
  upNextHref,
} from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { useOpenPreview } from "./ChartRow"
import { EpisodeRow } from "./EpisodeRow"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useShows } from "./hooks"
import { useTopShows, useUpNextShelf, useYouMightLike } from "./useHome"
import { useStatusBarStyle } from "./usePodcastsTheme"

/** A section's bold title with a grey chevron; tapping it opens the section's page. */
export function SectionHeader({
  title,
  onPress,
}: {
  title: string
  onPress: () => void
}) {
  return (
    <Pressable
      className="flex-row items-center gap-1 px-4 pt-6 pb-3"
      accessibilityRole="header"
      accessibilityLabel={title}
      onPress={onPress}
    >
      <Text className="text-3xl font-bold">{title}</Text>
      <Icon as={ChevronRight} size={24} className="text-muted-foreground" />
    </Pressable>
  )
}

function Section({ children }: { children: ReactNode }) {
  return <View className="px-4">{children}</View>
}

/**
 * The Home tab: "Up Next >" (episodes in progress, then the newest unplayed one of each show),
 * "Your Top Shows >" and "You Might Like >".
 */
export function Home() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const segments = useSegments()
  const openPreview = useOpenPreview()
  const shows = useShows().data ?? []
  const showById = new Map(shows.map((show) => [show.id, show]))
  const shelf = useUpNextShelf().data ?? []
  const top = useTopShows()
  const mightLike = useYouMightLike()

  return (
    <>
      <ScrollView
        className="bg-background flex-1"
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ paddingBottom: 24 }}
      >
        <SectionHeader
          title="Up Next"
          onPress={() => router.push(upNextHref(segments))}
        />
        <Section>
          {shelf.map(({ episode }) => {
            const show = showById.get(episode.showId)
            return show ? (
              <EpisodeRow
                key={episode.id}
                artwork
                episode={episode}
                show={show}
              />
            ) : null
          })}
        </Section>
        {top.length > 0 ? (
          <>
            <SectionHeader
              title="Your Top Shows"
              onPress={() => router.push(showsHref(segments))}
            />
            <Section>
              {top.map((show) => (
                <Pressable
                  key={show.id}
                  className="active:bg-secondary flex-row items-center gap-3 py-1"
                  accessibilityRole="button"
                  accessibilityLabel={show.title}
                  onPress={() => router.push(showHref(segments, show.id))}
                >
                  <Artwork uri={show.imageUrl} size={56} />
                  <Text className="flex-1 font-semibold" numberOfLines={2}>
                    {show.title}
                  </Text>
                </Pressable>
              ))}
            </Section>
          </>
        ) : null}
        {mightLike.length > 0 ? (
          <>
            <SectionHeader
              title="You Might Like"
              onPress={() => router.navigate(NEW_HREF)}
            />
            <Section>
              {mightLike.map((show) => (
                <Pressable
                  key={show.feedUrl}
                  className="active:bg-secondary flex-row items-center gap-3 py-1"
                  accessibilityRole="button"
                  accessibilityLabel={show.title}
                  onPress={() => openPreview(show.feedUrl)}
                >
                  <Artwork uri={show.imageUrl} size={56} />
                  <Text className="flex-1 font-semibold" numberOfLines={2}>
                    {show.title}
                  </Text>
                </Pressable>
              ))}
            </Section>
          </>
        ) : null}
      </ScrollView>
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        account
        title="Home"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
      />
    </>
  )
}
