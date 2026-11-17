# The Apple Podcasts look for the Books side

Mo asked on 2026-11-17 to "redesign rest of story teller app to look like Apple
podcast without changing the features outside podcast tab", and chose "Every
Books screen" over a colours-only or shared-pieces-only restyle. Mo accepted
that upstream Storyteller updates will then need hand merging in the restyled
files. The Podcasts section gets the same look in its own work
(`PODCASTS-DESIGN.md` and PR #48); both sides share the colours below.

The reference is Mo's ten screenshots of Apple Podcasts on iOS 26, kept outside
the repository in the project's files (`podcasts/apple-reference/`, 01 to 10).

## Rules

1. **No feature changes.** Every button, menu item, gesture, screen, route,
   setting and accessibility label stays and does what it did. Only where and
   how it is drawn changes. A control may move (for example Search becomes a
   round button in the bar) if it stays one tap from the same screen.
2. **Restyle, don't rewrite.** In upstream files keep the logic, hooks, handlers
   and the order of the code. Change class names, wrappers and layout. Don't
   reformat lines you don't change. Keep every `LOFI-FORK` marker. Restyled
   upstream files are listed in `tools/fork/touchpoints.json` under
   `allowedChanges` and in `FORK.md`.
3. **New shared pieces live in the fork's own folder**,
   `applications/mobile/apple-look/`, and screens import them.
4. **Colours come from theme tokens only** (`text-primary`, `bg-secondary`,
   `border-border` and their opacities), never hex values in components, so the
   Podcasts themes and both light and dark keep working.
5. **The reader's page is not restyled.** Book text, reading themes, reading
   fonts and highlights stay. Only the chrome around them changes.
6. **Android keeps working.** Keep the `usesSystemHeader` branches; Android
   draws the JavaScript header as before, in the new colours.

## Colours

Apple's colours become the app's own light and dark themes. They are appended to
`global.css` in one marked block (Uniwind allows `@import` only at the top of
the file, where it would be overridden by the upstream values below it). The
Podcasts section's "Like the app" theme follows them; its extra themes (Extra
Dark, Midnight, Paper, Forest) keep their own colours.

| Token              | Light     | Dark      | Apple name                       |
| ------------------ | --------- | --------- | -------------------------------- |
| background         | `#ffffff` | `#000000` | systemBackground                 |
| foreground         | `#000000` | `#ffffff` | label                            |
| card, popover      | `#ffffff` | `#1c1c1e` | secondarySystemGroupedBackground |
| primary, link      | `#9b42f5` | `#b57bff` | the Podcasts purple              |
| primary-foreground | `#ffffff` | `#ffffff` | text on a filled purple button   |
| secondary, muted   | `#f2f2f7` | `#1c1c1e` | systemGray6, grouped background  |
| muted-foreground   | `#8a8a8e` | `#8d8d93` | secondaryLabel                   |
| accent             | `#e5e5ea` | `#2c2c2e` | systemGray5 (pressed rows)       |
| destructive        | `#ff3b30` | `#ff453a` | systemRed                        |
| border             | `#c6c6c8` | `#38383a` | separator                        |
| input              | `#e5e5ea` | `#2c2c2e` | systemGray5                      |
| ring               | `#c7c7cc` | `#48484a` | systemGray3                      |

## Type

The system font (SF Pro on iOS) everywhere outside the reader's page: no
`fontFamily`, no `font-youngserif`. Sizes follow Apple's text styles:

- Large title 34 bold: the native header's large title on the main screens.
- Title 28 bold: a book's title on its page.
- Section heading 22 bold, with a chevron when it opens a list ("Currently
  reading ›").
- Row and body text 17, secondary lines 15 muted, captions 13 muted.

## Shapes

- **Covers:** rounded 8 on shelves and grids, 12 on the book page and the
  player, with a hairline `border-foreground/10` edge and no heavy shadow.
- **Buttons:** capsules. A main action is filled purple with white text. A
  second action is tinted (`bg-primary/15`, purple text), like Apple's "▶ 24m"
  pill. Bar buttons are the native toolbar's round glass buttons.
- **Grouped lists:** Apple's inset grouped style for settings and sheets: a
  muted heading over a rounded card (`bg-card` on `bg-secondary` in light,
  `bg-card` on black in dark), rows of 44 points or more, separators inset from
  the text, a muted chevron on rows that open a screen, switches in purple.
- **Mini player:** a floating glass capsule above the home indicator (Liquid
  Glass through `expo-glass-effect` on iOS 26, `bg-secondary` before it), with
  the cover, title, author or chapter, play and skip.

## Screen by screen

| Books screen                                                       | Like Apple's                    | What changes                                                                                                                                                                                          |
| ------------------------------------------------------------------ | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Home (`index.tsx`)                                                 | Home (10), Library (02)         | Native large title "Books" that shrinks on scroll. Side menu at the left; Search and a "…" menu (Import book, Settings) as round bar buttons. Shelves get "Title ›" headings and rounded covers.      |
| Shelf, author, narrator, series, collection, tag (`BookGrid`)      | Library's Recently Updated (02) | Large title, a grid of rounded covers with the title and author under each, the book count as a muted caption.                                                                                        |
| Search                                                             | Search (03)                     | Large title "Search" and a rounded search field with a magnifier, results in the same grid.                                                                                                           |
| Book page                                                          | Show page (06)                  | Big rounded cover, title 28 bold, authors in purple, narrators muted, the main action as a filled capsule and the others as tinted capsules, the description with "more", sections with "Title ›".    |
| Settings, server, log, custom themes and fonts, atmosphere section | Apple's grouped settings        | Inset grouped lists with muted headings, purple switches and chevrons.                                                                                                                                |
| Sheets: reading settings, speed, contents, bookmarks, footnote     | Apple's sheets                  | Native sheets with a grabber where they have room, grouped rows, capsule segmented controls.                                                                                                          |
| Listening player (`listen/[uuid].tsx`)                             | Player (08)                     | Background washed with the cover's colour, big rounded cover, title bold with the author muted, a slim rounded progress bar with elapsed and remaining time, large plain controls, the toolbar below. |
| Mini players (`MiniPlayerWidget`, `MiniPlayer`)                    | The mini player (10)            | The floating glass capsule.                                                                                                                                                                           |
| Reader chrome (`read/[uuid].tsx`, `Toolbar`, `SelectionMenu`)      | Apple's bars                    | Round glass bar buttons tinted purple and system type. The page itself is unchanged.                                                                                                                  |

## Milestones

All of them go into one pull request and one TestFlight build (with PR #48).

- **B1. Colours and font.** The `global.css` block, headings in the system font
  (`components/ui/text.tsx` and every `YoungSerif` or `font-youngserif` use on
  the Books side), the `apple-look/` folder registered as fork-owned.
- **B2. Shared pieces and Home.** `apple-look/`: the large-title bar, section
  heading, capsule buttons, grouped list and rows, glass capsule. The button,
  input, switch and slider in `components/ui/` restyled. Home, `Shelf`,
  `BookThumbnail` and the covers.
- **B3. Book page.**
- **B4. Grids and search.**
- **B5. Settings and sheets.**
- **B6. Players.**
- **B7. Reader chrome.**
- **B8. Look check.** Each screen read against this table and the screenshots,
  then the iOS build in CI and Mo's look on TestFlight.

Done when: `tools/fork/check.sh` passes, the fork check lists every restyled
upstream file under "allowed", the iOS build in Fork CI passes, and a review of
the diff finds no handler, menu item, label or screen removed.
