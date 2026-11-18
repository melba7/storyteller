# Podcasts redesign: the Apple Podcasts look, with every feature we have

Written 2026-11-17 for Mo's "redesign the whole thing to look like Apple podcast
app with all the features we have. Same animations, look and everything." It
replaces the Pocket Casts structure of PODCASTS-DESIGN.md (D1 to D5). That
document's ground rules still hold, except where this one says otherwise: no new
npm package, no new CSS variables (new values for existing ones in
`podcasts/themes.css` are fine), SF Symbols in native chrome, and the shared
haptics, EmptyState and PressableScale. Apple's app is a reference for layout
and motion only: no Apple artwork, logos, illustrations or names in the app. SF
Symbols are Apple's icons for apps and are fine.

Mo's screenshots of Apple Podcasts on their phone (iOS 26, 2026-11-17) are in
the project files at `/mnt/project-files/podcasts/apple-reference/` (not in the
public repository: they show other people's artwork and Mo's photo). Builders
look at them before writing a screen: 01 New, 02 Library, 03 Search, 04 Home
with a card's "…" menu open, 05 a show's episode list scrolled, 06 a show page,
07 a show page loading, 08 the player, 09 Home scrolled, 10 Home.

## Structure

| Apple Podcasts | Ours today                   | Ours after                                                  |
| -------------- | ---------------------------- | ----------------------------------------------------------- |
| Home           | Podcasts tab (library grid)  | Home: Up Next cards, Your Top Shows, You Might Like, charts |
| New            | Discover tab                 | New: featured cards, Top Shows with ranks, For You, charts  |
| Library        | Podcasts, Playlists, Up Next | Library: rooms and playlists as rows, then Recently Updated |
| Search         | search screens in two tabs   | Search tab: category tiles, then shows, episodes, spoken    |
| Account button | Profile tab                  | The round button at the top right opens Profile as a sheet  |
| Player queue   | Up Next tab                  | The player's queue button; Home's "Up Next >" page          |

- **Tab bar** (01, 10): iOS 26's floating glass bar with four tabs, Home
  (`house.fill`), New (`square.grid.2x2.fill`), Library (`square.stack.fill`)
  and Search (`magnifyingglass`, the system search tab, `role="search"`). The
  selected tab is purple on a glass pill. It minimizes on scroll to a round
  button at the left, the mini player in the middle and the search button at the
  right (05, 06).
- **Mini player** (10): a glass capsule above the bar: small rounded artwork,
  the title in bold on one line with the date under it, then play or pause and
  skip forward (the circular arrow with the seconds). It stays the tab bar's
  accessory.
- **Every tab root** (01, 02, 03, 10): a large bold title at the left and a
  round account button at the right (a person symbol on glass, since we have no
  account photo). Library also has a "…" glass button (Edit rows, New playlist,
  Add audio files, Import or Export OPML).
- **Home** (09, 10):
  - **"Up Next >"**: a section header (bold, about 28 pt, a grey chevron) over a
    horizontal shelf of cards, about two thirds of the screen wide and a third
    taller than wide, rounded about 16 pt, the next card peeking. A card is the
    artwork filling its top as a square, fading into a background of the
    artwork's colour, then: a tinted line ("New · 17h ago", "Resume · 5d ago"),
    the episode title in bold white (3 lines), one line of the description, and
    a bottom row with a translucent capsule (play symbol, and for a started
    episode a short progress bar, then the time left "19m"), a download symbol
    when not downloaded, and "…". Episodes: in progress first (latest played
    first), then the newest unplayed episode of each followed show (newest
    first, not archived), at most 20. Tapping a card opens the episode; the
    capsule plays it. "Up Next >" opens a page with the queue ("Playing Next")
    and then these episodes as rows.
  - **The card's "…" menu** (04): a native menu tinted by the card: a top row of
    two big buttons, Save (`bookmark`) and Share (`square.and.arrow.up`); then
    Play Next, Play Last, Mark as Played; then Go to Episode, Go to Show, View
    Transcript, Add to Playlist; then Download or Remove Download (red). Every
    "…" on an episode uses this menu.
  - **"Your Top Shows >"** (09): a shelf of square artwork (about 45% of the
    width, rounded about 10 pt) with the show's category in bold and "Updated
    Weekly" (from its episode dates) in grey under it. Shows ranked by time
    listened, then by recent plays.
  - **"You Might Like >"**: the same shelf from Discover's "For you".
  - **The charts** (Mo's ask, 2026-11-18): "Top Shows >", "Top Episodes" (pages
    of three ranked rows with a 60 pt cover) and eight "Top in ... >" shelves,
    the categories of followed shows first, then "Browse Categories" with the
    colour tiles. A new install shows them under "No podcasts yet". The plan and
    its reasons are in `docs/PODCASTS-LISTS-PLAN.md`.
- **New** (01): Discover without its search. A paging row of featured cards:
  square, filled edge to edge by the cover, with a grey caps label ("TOP SHOW"),
  the title and the author on a fade at the bottom. Then "Top Shows >": a shelf
  of square artwork with the rank number in bold, the title and the author under
  it. Then "For You >", "Top Episodes", a "Top in ... >" shelf for every other
  category, and the category tiles.
- **Covers** everywhere ask Apple's image server for a size that fits the frame
  on this screen (160, 320, 640 or 1280 px), and fall back to the original
  address, so chart covers are sharp. Shelves draw only the covers near the
  screen, and a loading shelf has the real shelf's height.
- **Library** (02): rows with a purple SF Symbol, the name in large type, an
  optional count in grey and a chevron, separators inset to the text: Shows
  (`square.stack`), Saved (`bookmark`), Downloaded (`arrow.down.circle`), Latest
  Episodes (`clock`), then each playlist (`dot.radiowaves.right` for smart ones,
  `list.bullet` for hand-filled ones) with its count, then History and
  Bookmarks. Then "Recently Updated": a two-column grid of square artwork with
  the show title in bold and a grey line under it (a dot for new episodes).
  Shows opens today's grid with its layouts, orders and Arrange.
- **Search** (03): the large title and account button, a rounded grey search
  field ("Shows, episodes and words said") and, while it is empty, a two-column
  grid of category tiles: rounded rectangles in a gradient of the category's
  colour, the name in bold white at the bottom left, and a large SF Symbol in a
  lighter shade at the top right. Typing shows scopes (All podcasts, Your shows,
  Spoken) with shows and episodes. Pasted feed and Apple Podcasts links still
  follow.
- **Profile sheet** (from the account button): today's Profile (the stats card,
  Playback, Ad skipping, Downloads, Notifications, Appearance, OPML, Apple
  Podcasts sync, Stats, History, Bookmarks) in grouped cards, with Done.

## Look

- **Type**: SF Pro (the system font) everywhere in Podcasts, bold for titles, as
  Apple does. The brand serif leaves the Podcasts section.
- **Colour**: Apple's purple accent (`#9B42F5` light, `#B57BFF` dark, close to
  the screenshots) and the system backgrounds come from the app's own light and
  dark theme, which the Books restyle gives Apple's colours for the whole app.
  The Podcasts screens use theme tokens only, so the other Podcasts themes keep
  working with their own primary.
- **Episode rows** (05, 06): a grey line "Oct 6 · 5h ago" style date (with the
  season or "Played" when it applies), the title in bold (up to 4 lines), one or
  two grey lines of description, the episode's artwork at the right (about 96
  pt, rounded 8 pt, top-aligned), and a bottom row: a light grey capsule with a
  purple play symbol and the length or time left in bold purple (a short
  progress bar when started, "Played" when played), and "…" in grey at the far
  right. Separators inset to the content. Swipe actions stay.
- **Show page** (06, 07): the artwork fills the top edge to edge, under the
  status bar and the glass buttons (back at the left; filter, sort and "…" in
  one glass capsule at the right). At its bottom edge: a white capsule "▶ Latest
  Episode" (or "▶ Resume" / "▶ Play") and a round glass "+" to follow (a check
  when followed). The artwork's colour continues below: the description in white
  (2 lines, "MORE" in bold at the right), then a tinted line: category · how
  often · publisher. Then the page turns to the system background: "Episodes >"
  and the rows.
- **Episode page**: the same colour header with the episode's artwork, date,
  title and show, a white "▶ Play" capsule with the length, then the notes,
  chapters, people, support links and found ads.
- **Player** (08): a sheet with a grabber, the artwork's colour as the whole
  background, the artwork large and rounded (shrinking a little when paused).
  Under it at the left: the date in a tinted colour, the title in bold white
  (one line, fading out at the right) with "…" at the right, the show's name in
  the tinted colour. A thick rounded scrubber (light fill, darker rest) with
  elapsed and "−left" times under it; the chapter title between them when there
  are chapters. Transport row: speed ("1×") at the left, skip back, a big play
  or pause (no circle), skip forward (circular arrows with the seconds), and the
  sleep timer (`moon.zzz`) at the right. A volume slider with speaker symbols. A
  bottom row: transcript (`quote.bubble`) at the left, AirPlay in the middle,
  the queue (`list.bullet`) at the right. The transcript replaces the artwork in
  place; the queue opens "Playing Next" in place of the artwork with drag, swipe
  and Clear. The "…" menu: Save, Share; Go to Episode, Go to Show; Chapters,
  Bookmark this moment, Bookmarks; Notes; Show settings.
- **Glass buttons**: native toolbar buttons (Stack.Toolbar) wherever a bar
  exists; round glass buttons drawn in content use `@expo/ui` SwiftUI
  `glassEffect` where it renders, else a translucent white circle.
- **Motion**: native first: glass, menus, sheets and the tab bar's minimizing
  are drawn by iOS. The player grows out of the mini player (expo-router's zoom
  transition, `Link.AppleZoom`, if it works from the bar's accessory, else the
  modal sheet); artwork zooms into the show page from shelves and grids; cards
  and capsules press in a little (PressableScale); shelves snap card by card;
  the player artwork springs on play and pause. Reduce Motion turns these into
  fades.

## Milestones (each one session, in the same pull request as R1 to R8)

- **A1. Tabs and rooms**: the four tabs and their stacks, the shared detail
  routes, the account button and Profile as a sheet, the Library list (rooms,
  playlists, History, Bookmarks) and Recently Updated grid, Shows as its own
  screen, Search as the search tab (today's searches inside it), New as
  Discover, Home with its sections as plain lists for now, the Up Next page with
  the queue. Route tests updated; nothing lost from Profile, Playlists or Up
  Next.
- **A2. Home**: the Up Next cards and their data (SQL tested), the shared
  episode "…" menu (04), Your Top Shows, You Might Like, and the Saved and
  Latest Episodes screens.
- **A3. Rows, show page and episode page** (05, 06, 07), the purple accent and
  system type.
- **A4. Player and mini player** (08, 10), the queue and transcript in place,
  the zoom from the mini player.
- **A5. Search and New** (01, 03): the category tiles and scopes, the featured
  cards and ranked Top Shows.
- **A6. Look and motion check**: every screen against the screenshots in Light
  and Dark and the other themes, press and spring animations, Reduce Motion,
  VoiceOver labels and large text; Opus checks, Sonnet fixes.

## Sources

- Mo's screenshots (above).
- Apple Podcasts on iOS 26 (Browse renamed New, search at the bottom, speeds,
  Enhance Dialogue): https://www.macrumors.com/guide/ios-26-podcasts/
- iOS 27.2's Home with "New Episodes" and "Continue Playing" (Mo's phone still
  shows "Up Next", so that is followed):
  https://9to5mac.com/2026/10/20/ios-27-2-adds-new-features-in-six-iphone-apps-heres-whats-coming
