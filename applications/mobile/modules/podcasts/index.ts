// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import { requireOptionalNativeModule } from "expo-modules-core"

/** A podcast feed as the Swift side reads it. A value the feed lacks is missing or null. */
export type PodcastFeedData = {
  title: string
  author?: string | null
  /** Plain text. */
  description: string
  imageUrl?: string | null
  link?: string | null
  language?: string | null
  /** In feed order. */
  episodes: PodcastFeedEpisode[]
}

export type PodcastFeedEpisode = {
  guid: string
  title: string
  /** Milliseconds since 1970. */
  publishedAt?: number | null
  durationSeconds?: number | null
  /** Plain text. */
  notes: string
  audioUrl: string
  audioType: string
  audioBytes?: number | null
  imageUrl?: string | null
  season?: number | null
  number?: number | null
}

type PodcastsNativeModule = {
  /** Downloads and reads the feed. Rejects with a message the listener can read. */
  fetchFeed(url: string): Promise<PodcastFeedData>
}

/** The native module. Null on Android and the web, where the section is not available. */
export const Podcasts =
  requireOptionalNativeModule<PodcastsNativeModule>("Podcasts")
