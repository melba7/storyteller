// LOFI-FORK: the podcasts section's hosts, guests and support links (see FORK.md).
//
// Pure rules for the feed's `podcast:person` and `podcast:funding` tags: reading what was
// saved as JSON text, and which people an episode shows.
import type { PodcastFunding, PodcastPerson } from "./index"

export const MAX_PEOPLE = 20
export const MAX_FUNDING = 5

/** The address when it is http or https, otherwise null. Only these may be opened. */
export function webUrl(value: unknown): string | null {
  return typeof value === "string" && /^https?:\/\/\S+$/i.test(value.trim())
    ? value.trim()
    : null
}

function parseList(value: unknown): unknown[] {
  if (typeof value !== "string") return []
  try {
    const parsed: unknown = JSON.parse(value)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function text(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() !== ""
    ? value.trim()
    : fallback
}

/**
 * Reads the saved JSON list of people. Anything that isn't a list gives none; an entry with
 * no name is dropped, missing roles and groups get the spec's defaults, and a picture or
 * link that isn't http(s) is left out.
 */
export function peopleFromJson(value: unknown): PodcastPerson[] {
  const people: PodcastPerson[] = []
  for (const entry of parseList(value)) {
    if (!isRecord(entry)) continue
    const name = text(entry["name"], "")
    if (name === "") continue
    people.push({
      name,
      role: text(entry["role"], "host").toLowerCase(),
      group: text(entry["group"], "cast").toLowerCase(),
      img: webUrl(entry["img"]),
      href: webUrl(entry["href"]),
    })
    if (people.length === MAX_PEOPLE) break
  }
  return people
}

/** Reads the saved JSON list of support links; only http(s) addresses are kept. */
export function fundingFromJson(value: unknown): PodcastFunding[] {
  const links: PodcastFunding[] = []
  for (const entry of parseList(value)) {
    if (!isRecord(entry)) continue
    const url = webUrl(entry["url"])
    if (url === null || links.some((link) => link.url === url)) continue
    links.push({ url, label: text(entry["label"], "") })
    if (links.length === MAX_FUNDING) break
  }
  return links
}

/** The text to save in a column; "[]" when there is nothing. */
export function toJson(list: readonly unknown[] | null | undefined): string {
  return JSON.stringify(list ?? [])
}

export function samePeople(
  a: readonly PodcastPerson[],
  b: readonly PodcastPerson[],
): boolean {
  return JSON.stringify(a) === JSON.stringify(b)
}

/**
 * The people to show for an episode. As the Podcasting 2.0 spec says, an episode's own
 * people replace the show's; with none of its own, the show's are used.
 */
export function peopleForEpisode(
  episode: { people: readonly PodcastPerson[] },
  show: { people: readonly PodcastPerson[] } | null | undefined,
): PodcastPerson[] {
  return episode.people.length > 0
    ? [...episode.people]
    : [...(show?.people ?? [])]
}
