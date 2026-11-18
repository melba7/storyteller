// LOFI-FORK: the podcasts section's episode menu rules (see FORK.md).
//
// What the episode "..." menu offers and in which order (Apple's): a top row of Save and Share,
// then groups drawn with a line between them. The screen binds each id to what it does.

export type MenuItemId =
  | "save"
  | "share"
  | "next"
  | "last"
  | "remove-queued"
  | "played"
  | "episode"
  | "show"
  | "transcript"
  | "playlist"
  | "archive"
  | "download"

export type MenuItem = {
  id: string
  title: string
  /** An SF Symbol name. */
  icon: string
  destructive?: boolean
}

export type MenuLayout = {
  /** The two big buttons across the top. */
  top: MenuItem[]
  /** The groups below, each set apart by a line. Never empty. */
  groups: MenuItem[][]
}

export type MenuFacts = {
  starred: boolean
  played: boolean
  archived: boolean
  queued: boolean
  /** A preview episode isn't in the library: no Save, played mark, archive, or pages. */
  preview: boolean
  /** The player has this episode loaded, so it has a transcript to open. Default false. */
  transcript?: boolean
  /** The page the menu is on: its own "Go to" entry is left out. */
  here?: { episode?: boolean; show?: boolean }
  /** The download entry's title and whether it is destructive; null when there is none. */
  download: { title: string; destructive: boolean; icon: string } | null
  /** Extra entries for an added file, in their own group after Archive. */
  extra?: MenuItem[]
}

/** The menu for an episode. */
export function menuLayout(facts: MenuFacts): MenuLayout {
  const top: MenuItem[] = [
    ...(facts.preview
      ? []
      : [
          {
            id: "save",
            title: facts.starred ? "Unsave" : "Save",
            icon: facts.starred ? "bookmark.fill" : "bookmark",
          },
        ]),
    { id: "share", title: "Share", icon: "square.and.arrow.up" },
  ]
  const queueing: MenuItem[] = [
    {
      id: "next",
      title: "Play Next",
      icon: "text.line.first.and.arrowtriangle.forward",
    },
    {
      id: "last",
      title: "Play Last",
      icon: "text.line.last.and.arrowtriangle.forward",
    },
    ...(facts.queued
      ? [
          {
            id: "remove-queued",
            title: "Remove from Up Next",
            icon: "minus.circle",
            destructive: true,
          },
        ]
      : []),
    ...(facts.preview
      ? []
      : [
          {
            id: "played",
            title: facts.played ? "Mark as Unplayed" : "Mark as Played",
            icon: facts.played ? "circle" : "checkmark.circle",
          },
        ]),
  ]
  const pages: MenuItem[] = [
    ...(facts.preview
      ? []
      : [
          ...(facts.here?.episode
            ? []
            : [{ id: "episode", title: "Go to Episode", icon: "info.circle" }]),
          ...(facts.here?.show
            ? []
            : [
                {
                  id: "show",
                  title: "Go to Show",
                  icon: "dot.radiowaves.up.forward",
                },
              ]),
          ...(facts.transcript
            ? [
                {
                  id: "transcript",
                  title: "View Transcript",
                  icon: "quote.bubble",
                },
              ]
            : []),
        ]),
    { id: "playlist", title: "Add to Playlist", icon: "text.badge.plus" },
  ]
  const keeping: MenuItem[] = [
    ...(facts.preview
      ? []
      : [
          {
            id: "archive",
            title: facts.archived ? "Unarchive" : "Archive",
            icon: facts.archived ? "tray.and.arrow.up" : "archivebox",
          },
        ]),
    ...(facts.extra ?? []),
  ]
  const download: MenuItem[] = facts.download
    ? [
        {
          id: "download",
          title: facts.download.title,
          icon: facts.download.icon,
          destructive: facts.download.destructive,
        },
      ]
    : []
  return {
    top,
    groups: [queueing, pages, keeping, download].filter(
      (group) => group.length > 0,
    ),
  }
}

/** The SF Symbol for what a download entry does. */
export function downloadIcon(
  action: "download" | "retry" | "cancel" | "delete",
) {
  switch (action) {
    case "download":
    case "retry":
      return "arrow.down.circle"
    case "cancel":
      return "xmark.circle"
    case "delete":
      return "trash"
  }
}
