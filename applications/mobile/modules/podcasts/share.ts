// LOFI-FORK: the podcasts section's sharing (see FORK.md).
//
// What to say when the listener shares a show, an episode or the place playing now. The
// messages are made here so they can be tested; the share sheet is React Native's Share.
// An episode has no web page of its own in the library, so an episode is shared by its
// audio address.
import { formatTime } from "./playbackRules"

export type ShareMessage = {
  /** The subject, for apps that have one (mail). */
  title: string
  message: string
}

type ShowInfo = { title: string; feedUrl: string; link: string | null }
type EpisodeInfo = { title: string; audioUrl: string }

/** Only web addresses are worth sending to someone. */
function webLink(value: string | null | undefined): string | null {
  const text = value?.trim() ?? ""
  return /^https?:\/\/\S+$/i.test(text) ? text : null
}

/** A show: its name, its feed link and, when it has one, its web page. */
export function showShare(show: ShowInfo): ShareMessage {
  const lines = [show.title]
  const feed = webLink(show.feedUrl)
  if (feed) lines.push(`Feed: ${feed}`)
  const page = webLink(show.link)
  if (page) lines.push(`Web: ${page}`)
  return { title: show.title, message: lines.join("\n") }
}

/** An episode: its title, the show's and its audio address. Null with no usable address. */
export function episodeShare(
  episode: EpisodeInfo,
  show: { title: string } | null,
): ShareMessage | null {
  const audio = webLink(episode.audioUrl)
  if (!audio) return null
  const lines = [episode.title]
  if (show?.title) lines.push(show.title)
  lines.push(audio)
  return { title: episode.title, message: lines.join("\n") }
}

/** The place playing now: the episode and "at 12:34". Null with no usable address. */
export function placeShare(
  episode: EpisodeInfo,
  show: { title: string } | null,
  position: number,
): ShareMessage | null {
  const audio = webLink(episode.audioUrl)
  if (!audio) return null
  const lines = [`${episode.title} at ${formatTime(position)}`]
  if (show?.title) lines.push(show.title)
  lines.push(audio)
  return { title: episode.title, message: lines.join("\n") }
}
