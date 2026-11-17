// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Linking, Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import type { PodcastFunding, PodcastPerson } from "@/modules/podcasts"
import { webUrl } from "@/modules/podcasts/people"

import { Artwork } from "./Artwork"

function open(url: string) {
  // Only web addresses open; a link the phone can't open is ignored.
  if (webUrl(url) === null) return
  Linking.openURL(url).catch(() => {})
}

/** "Support the show" links and the hosts and guests, under an episode's notes. */
export function EpisodePeople({
  people,
  funding,
}: {
  people: readonly PodcastPerson[]
  funding: readonly PodcastFunding[]
}) {
  if (people.length === 0 && funding.length === 0) return null
  return (
    <View className="w-full gap-4 pt-4">
      {funding.length > 0 ? (
        <View className="gap-2">
          <Text className="text-lg font-bold" accessibilityRole="header">
            Support the show
          </Text>
          {funding.map((link) => (
            <Pressable
              key={link.url}
              accessibilityRole="link"
              accessibilityLabel={link.label || "Support the show"}
              onPress={() => open(link.url)}
              className="min-h-11 justify-center"
            >
              <Text className="text-primary text-base underline">
                {link.label || "Support the show"}
              </Text>
            </Pressable>
          ))}
        </View>
      ) : null}
      {people.length > 0 ? (
        <View className="gap-2">
          <Text className="text-lg font-bold" accessibilityRole="header">
            Hosts and guests
          </Text>
          {people.map((person, index) => (
            <Person key={`${person.name}-${index}`} person={person} />
          ))}
        </View>
      ) : null}
    </View>
  )
}

function Person({ person }: { person: PodcastPerson }) {
  const href = webUrl(person.href)
  const label = `${person.name}, ${person.role}`
  const body = (
    <View className="min-h-11 flex-row items-center gap-3">
      <Artwork uri={webUrl(person.img)} size={40} className="rounded-full" />
      <View className="flex-1">
        <Text className={href ? "text-primary text-base" : "text-base"}>
          {person.name}
        </Text>
        <Text className="text-muted-foreground text-sm capitalize">
          {person.role}
        </Text>
      </View>
    </View>
  )
  if (!href) {
    return (
      <View accessible accessibilityLabel={label}>
        {body}
      </View>
    )
  }
  return (
    <Pressable
      accessibilityRole="link"
      accessibilityLabel={label}
      accessibilityHint="Opens their page"
      onPress={() => open(href)}
    >
      {body}
    </Pressable>
  )
}
