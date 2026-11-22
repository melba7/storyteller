// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// The words on the four ad switches in Profile, in the order they are shown.
import type { AdSkipSettings } from "./index"

export type AdSwitchRow = {
  key: keyof AdSkipSettings
  title: string
  body: string
}

export const AD_SWITCHES: readonly AdSwitchRow[] = [
  {
    key: "skipAds",
    title: "Sponsor ads",
    body: "Skips the ads other companies pay for.",
  },
  {
    key: "skipOwnPlugs",
    title: "The hosts' own plugs",
    body: "Skips the hosts asking for support: Patreon, merch, or a review.",
  },
  {
    key: "skipPromos",
    title: "Promos",
    body: "Skips promos for other shows, live events and subscriptions.",
  },
  {
    key: "skipCredits",
    title: "Intros and credits",
    body: "Skips the music and the thanks at the start and the end.",
  },
]
