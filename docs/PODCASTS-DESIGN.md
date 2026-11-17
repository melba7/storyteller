# Podcasts design plan: a modern podcast app look

Written 2026-11-17 for Mo's "make it like a modern podcast app". Pocket Casts
stays the structure; other apps give patterns only (no code, names, icons or
artwork).

## Today, read from the code

Correct, themed and labelled, but flat: custom top bars and no large titles;
colour only in the player; a centred show page with three trailing controls per
row and played rows at 50%; an episode card of ten stacked buttons; a player
pushed from the right whose speed panel shoves the page; two text fields in
Discover; a Profile that doesn't scroll (a bug); no motion or haptics. The mini
player is already iOS 26's native accessory.

## Design direction

1. **Let iOS draw the chrome**: native large titles, glass bar buttons, search,
   sheets and SF Symbol menus; the tab bar shrinks on scroll. Glass only where
   the system draws it.
2. **The artwork sets the colour**: a gradient in the player, a soft wash on the
   show page and card, blurred artwork on Discover's hero cards. Text never sits
   on bare artwork.
3. **One hierarchy per screen**: a big title, one primary action (a filled
   capsule), the rest as quiet icons or in "…". Text is left-aligned; only the
   player and empty states centre.
4. **Fewer, calmer controls**: four buttons plus "…" in the player (Pocket
   Casts' toolbar pattern), two trailing controls per episode row. A Snipd
   review found its busy screens confusing.
5. **Motion explains state, haptics confirm actions**: artwork shrinks when
   paused, the seek bar thickens under the finger, nothing animates on frequent
   taps, Reduce Motion is honoured.
6. **Rounder, roomier, title case**: radii 8, 12 and 24 pt plus capsules; 16 pt
   gutters, 24 pt between sections; title-case section headers as on iOS 26.
7. **Every theme, every reader**: six themes, a VoiceOver label on every icon,
   no fixed text heights (Dynamic Type), and text contrast of at least 4.5:1,
   checked by tests where possible.

## Ground rules for the coder

- **No new npm package.** Use expo-router 58 (`Stack.Title`
  `large`/`largeStyle`, `Stack.Toolbar` Button/Menu/View with SF Symbol `icon`s,
  `Stack.SearchBar`, NativeTabs `minimizeBehavior`), reanimated 4.7
  (`useReducedMotion`), gesture handler, expo-haptics, expo-image `blurRadius`,
  react-native-svg, and React Native 0.88's
  `backgroundImage: "linear-gradient(...)"` and `boxShadow`. Don't import
  expo-blur or expo-glass-effect (not direct dependencies).
- **No new CSS variables**: they would touch upstream `global.css`, and
  `theme.test.ts` wants the same set in every theme. Use tokens with opacity
  (`bg-primary/15`, `border-foreground/10`). Cards use `bg-secondary`, because
  `--color-card` equals the background in Light, Dark and Extra Dark; separators
  in cards use `border-foreground/10`, because in Dark `--color-border` equals
  `--color-secondary`.
- **Icons**: SF Symbols in native chrome (tabs, toolbar buttons, menu item
  `image`s), lucide in React content (Mo's choice in PODCASTS-PLAN).
- **New shared pieces**: `podcasts/haptics.ts` (`tap()`, `pick()`, `done()`:
  light impact, selection, success; errors caught), `podcasts/EmptyState.tsx`
  (icon in a `bg-primary/15` circle, `text-xl font-bold` title, muted body,
  optional primary capsule), `podcasts/PressableScale.tsx` (springs to 0.96; 0.7
  opacity with Reduce Motion), and `modules/podcasts/artworkTint.ts` with its
  test.
- **Checking**: vitest for pure helpers, `tools/fork/check.sh` and Fork CI's iOS
  build. CI takes no screenshots (its Debug simulator app needs Metro), so Mo
  checks TestFlight in all six themes, Midnight on a light iPhone, with
  VoiceOver, the largest text size, Reduce Motion and Reduce Transparency.

## Screen by screen

### All screens: native iOS 26 bars (D1)

- **`ScreenBar.tsx` becomes the native header.** It keeps `title`, `left` and
  `right`, adds `large` and `titleHidden`, renders `<Stack.Title large={large}>`
  in `--color-foreground` with `largeStyle={{ fontFamily: "YoungSerif" }}` (the
  brand type stays), and puts `left`/`right` in `<Stack.Toolbar placement=...>`
  (React content in `Stack.Toolbar.View`, or native
  `Stack.Toolbar.Button`/`Menu` children). Screens only drop their `pt-safe`
  wrapper.
- **`TabStack.tsx`**: `headerShown`, `headerTransparent`,
  `headerShadowVisible: false`, `headerBackButtonDisplayMode: "minimal"`, and
  `statusBarStyle` from `usePodcastsTheme().dark` (closing the status-bar item
  in PLAN.md's Later; the four screens' `StatusBar` get the same `style`). The
  episode sheet stays headerless.
- **Large titles** on the five tab roots, small inline titles on pushed pages. A
  large title needs a scroll view as the screen's first child; most lists
  already set `contentInsetAdjustmentBehavior="automatic"`, and `Profile.tsx`
  gets a `ScrollView` (which also fixes the screen that doesn't scroll).
- **Toolbars with SF Symbols**: Podcasts gets `magnifyingglass`, `plus` and an
  `ellipsis` menu (Layout, Sort by, Add audio files, Arrange). Playlists gets a
  `plus` menu in place of the Alert. Up Next gets a "Clear" text button. The
  show page gets `arrow.up.arrow.down` (the sort menu from `ShowBarButtons.tsx`)
  and an `ellipsis` menu (Select episodes, Share, Settings, and Unfollow as
  destructive). The side menu button goes on the left in a `Stack.Toolbar.View`.
- **`(tabs)/_layout.tsx`**: `minimizeBehavior="onScrollDown"`; the mini player
  already handles the inline placement, as Pocket Casts' does since its glass
  update.
- **`podcasts/_layout.tsx`**: the player gets `presentation: "modal"`, so it
  slides up and swipes down. The chevron stays for VoiceOver.
- **`MiniPlayer.tsx`**: a skip-ahead button (lucide `RotateCw` with the seconds)
  in the full placement, `rounded-lg` artwork, the time left in its VoiceOver
  label, `tap()` on play/pause.
- **Risks** (so convert the Podcasts tab first and try it on TestFlight): the
  glass takes its light or dark look from iOS, not the Podcasts theme; a large
  title may not shrink while `SelectionBar` sits above a list (fine while
  selecting); toolbars must work in per-tab stacks.

### Player (D2)

- **Background**: `playerGradient(color)` in `artworkTint.ts`. The top is
  today's `playerBackground` after `vivid()` raises saturation (the measured
  average is often greyish; fixing it here leaves the Swift alone), the bottom
  is the top at 55% brightness, and both stay under the brightness cap so white
  text keeps 4.5:1. Drawn as the style
  `backgroundImage: "linear-gradient(180deg, <top>, <bottom>)"`.
- **Top bar**: the chevron, then page pills (Now Playing · Notes · Chapters when
  there are any · Transcript) in a sideways `ScrollView`, so they fit at large
  text sizes. Selected: `bg-white` with black text; others `bg-white/15`. The
  row is a `tablist` and each pill a selectable `tab`. This replaces the two
  toggles, and the notes get their own page, so the main page fits one screen.
- **Now Playing page**: artwork `min(width - 48, 360)`, `rounded-2xl`,
  `boxShadow: "0 16px 40px rgba(0,0,0,0.35)"`, springing to 0.88 when paused
  (not with Reduce Motion). Left-aligned
  `text-2xl font-bold tracking-tight text-white` title over the show name in
  `text-base text-white/70`.
- **`SeekBar.tsx`**: while touched, the track animates from `h-1` to `h-2` and
  the thumb from 14 to 20 pt. Time labels get `fontVariant: ["tabular-nums"]` so
  they don't jitter. Ad marks stay.
- **Transport**: unchanged layout. `tap()` on play/pause and skips; `pick()`
  when the seek bar is let go and on a chapter jump.
- **Toolbar**: a new `PlayerToolbar.tsx` replaces `PlayerButtons.tsx` with five
  even 44 pt slots above `pb-safe`: speed ("1.5×"), sleep (moon, or minutes
  left), AirPlay, bookmark, and "…" (Star/Unstar, Add to playlist, Share this
  place). White icons; a pressed slot shows `bg-white/15`. `LibraryButtons.tsx`
  keeps only the bookmark button, and `ShareButton.tsx` exports its share
  function for the menu.
- **Speed** opens in a bottom sheet built like `SleepTimerSheet`. The current
  speed is in `text-3xl`; the selected preset is white with black text, never
  faint grey (the readability problem reported in Apple's iOS 26 speed panel).
- Split `PlayerScreen.tsx` into `PlayerScreen`, `PlayerNowPlaying.tsx` and
  `PlayerPages.tsx` to stay under 300 lines. `ChapterBar`, `SkippedAdNote`,
  `TranscriptView` and `ChapterList` keep their insides.

### Show page (D3)

- **`ShowHeader.tsx`**: a wash runs behind the transparent bar to 32 pt below
  the artwork (a gradient from the artwork colour at `headerWash()` alpha to
  transparent). Then the 200 pt artwork (`rounded-2xl`, soft shadow), a centred
  `text-2xl font-bold` title, the author in muted `text-base`, a meta line
  ("Comedy · 214 episodes"), and one row: Follow as a filled primary capsule
  (Following: `bg-secondary` with a check) beside a round `bg-secondary` share
  button.
- **`headerWash(color, background, foreground)`** picks the strongest alpha from
  0.15 to 0.45 that keeps the theme's foreground at 4.5:1 over the blend.
- **`ensureArtworkColor(show)`** moves from `playback.ts` (`tintFor`) into
  `modules/podcasts/`, so a show page opened without a colour measures it too.
  It writes the existing `artwork_color` column, so the schema doesn't change.
- **`PodcastShow.tsx`**: the bar's title appears only once the header title
  scrolls under it. An "Episodes" heading (`text-xl font-bold`, the sort in
  muted text) sits over the list.

### Episode rows (D3, `EpisodeRow.tsx`)

- **Layout**: [optional 56 pt `rounded-lg` artwork] [date and star /
  `font-semibold` title on two lines / meta line] ["…"] [play]. The meta line
  holds a small download glyph (a check when downloaded, a mini ring while
  downloading, an alert after a failure), the length or time left, and "Up Next"
  in primary. A new `artwork` prop is on in PlaylistScreen, History and the
  preview.
- **The download button leaves the row.** `EpisodeMenu` gains Download, Cancel
  download and Remove download at the top (from `downloadLook` and
  `pressDownload`); the card keeps `DownloadButton`. "…" becomes a quiet 20 pt
  muted icon with a 44 pt target.
- **`PlayButton`**: the face shrinks to 36 pt (`hitSlop` keeps 44 pt),
  `bg-primary/15` with a primary glyph, filled `bg-primary` while it plays. The
  ring is unchanged.
- **Played rows** drop the 50% opacity, which takes muted text below 3:1. Title
  and meta go `text-muted-foreground`, the meta says "Played" with a check, and
  the artwork goes to 60%.
- **VoiceOver**: the glyph is hidden, so the row label says "Downloaded" or
  "Downloading, 40%". A pure, tested `rowMeta()` in `episodeLook.ts` builds that
  text and the visible meta line. Separators become `border-foreground/10`.

### Episode card (D3, `PodcastEpisode.tsx`)

- A wash from the show's colour; a left-aligned header (72 pt artwork, show
  title in `text-sm font-semibold text-primary`, date · length); the title in
  `text-2xl font-bold`; then one full-width primary capsule ("Play", "Resume ·
  32 min left" or "Pause").
- A new `EpisodeActions.tsx` strip of five 48 pt round `bg-secondary` buttons
  with 12 pt captions: Up Next (a menu of Play next, Play last, Remove),
  Download, Played, Star, and More (Add to playlist, Archive, Share, local-file
  actions). It wraps at large text sizes, reuses `starAction`, `playedAction`
  and `archiveAction`, and absorbs `QueueButtons.tsx`.
- Then the status line, AdsFound, Bookmarks, Notes and Hosts and guests, each
  under a `text-lg font-bold` heading.

### Podcasts grid (D4)

- **`Artwork.tsx`**: corners follow size (`rounded-lg` to 56 pt, `rounded-xl` to
  140 pt, then `rounded-2xl`) with a hairline `border border-foreground/10`, so
  light artwork keeps an edge.
- **`LibraryShows.tsx`**: the badge gets `min-h-5 min-w-5` (the fixed `h-5`
  clips at large text sizes) and `border-2 border-background`, and sits on the
  corner (`-top-1.5 -right-1.5`). Cells use `PressableScale`.
  **`PodcastsHome.tsx`**: an `EmptyState` with a "Find a podcast" button to
  Discover, and refresh errors in a `bg-destructive/10 rounded-xl p-3` note.

### Discover and search (D4)

- **Search**: `Stack.SearchBar` ("Search podcasts or paste a link") replaces
  both text fields. When the text is a link, a "Follow this link" row above the
  results calls the existing `add()`. A new, tested `isFollowLink(text)` in
  `followLink.ts` decides (an http(s) or Apple Podcasts link). Result artwork is
  64 pt `rounded-xl`.
- **With nothing typed** (`DiscoverBrowse.tsx`, `ChartRow.tsx`):
  1. **Hero carousel**: the top chart's first five as `rounded-3xl` cards
     (screen width minus 32 pt, 220 pt tall), snapping with `snapToInterval` and
     `decelerationRate="fast"`. Blurred artwork (expo-image `blurRadius={40}`)
     under a 60% black scrim keeps white text at 4.5:1 even on white art. On it:
     the 140 pt artwork, "#1", the title in `text-xl font-bold text-white`, the
     author. VoiceOver: "Number 1, title, author".
  2. **Rows**: `text-xl font-bold` headings ("Because you follow …" muted under
     them), 140 pt `rounded-xl` tiles with `PressableScale`. "Top podcasts"
     continues from #6.
  3. **Categories**: a 2-column grid of `h-20 rounded-2xl bg-secondary` tiles
     with a primary lucide icon (a fixed id→icon map, such as Comedy→`Laugh`)
     and the name on up to two lines.
- **`CategoryChart.tsx`**: ranks in `text-2xl font-bold` tabular figures, 64 pt
  artwork. **`SearchEpisodes.tsx`**: the native search bar, and `Segments` as a
  capsule segmented control (`bg-secondary` track, `bg-background` thumb).

### Up Next, Playlists, Profile, Stats (D5)

- **Up Next**: the summary under the large title; 56 pt `rounded-lg` artwork; a
  2 pt progress line once started (`bg-foreground/10` track, `bg-primary` fill);
  swipe buttons with an icon over the label (`ArrowUpToLine`, `ArrowDownToLine`,
  `Trash2`); `pick()` on a swipe action and a `DragList` drop; an empty state
  with a button to the Podcasts tab.
- **Playlists**: a 44 pt `rounded-xl bg-primary/15` icon tile per row
  (`Sparkles` smart, `ListMusic` hand-filled), title, "12 episodes · rules"
  muted, chevron; an empty state with "New playlist"; PlaylistScreen shows its
  rules as pills and turns row artwork on.
- **Profile**: a new `SettingsGroup.tsx` with a title-case muted header over a
  `bg-secondary rounded-3xl px-4 overflow-hidden` card, rows split by
  `border-foreground/10` (an inner `-mb-px` hides the last line). On top, a
  stats card (Listened and Saved in `text-3xl font-bold tabular-nums`) that
  opens Stats. Then Library (Downloads, History, Bookmarks), Downloads (Wi-Fi
  only, Download new, Delete played, Notify), Playback, Appearance, Your files,
  OPML and Ad skipping, with no `uppercase` headers.
- **Stats**: "Time listened" in `text-4xl font-bold`, "Time saved" in a card,
  `rounded-t-md` bars. History, Downloads and Bookmarks get `EmptyState`.

## Milestones (most modern-feeling first)

- [ ] **D1. Native iOS 26 bars** (M to L): `ScreenBar`, `TabStack`, both
      layouts, `MiniPlayer`, `ShowBarButtons`, `Profile`, each screen's
      `pt-safe`. Done when `check.sh` passes, Fork CI builds, and on TestFlight
      every screen has the native bar, tab titles shrink on scroll, the tab bar
      shrinks with the mini player inline, the player swipes down, Profile
      scrolls to Ad skipping, Midnight on a light iPhone reads well, and
      VoiceOver reads every toolbar button.
- [ ] **D2. The player** (M to L): `artworkTint.ts` and its test, `haptics.ts`,
      the player files, `SeekBar`, `SpeedPanel`, `SleepTimerSheet` (button
      only), `LibraryButtons`, `ShareButton`. Done when the test shows white
      text at 4.5:1 on both gradient ends for 10 sample colours (white, yellow,
      black among them), nothing jumps when speed opens, the artwork shrinks
      when paused (not with Reduce Motion), VoiceOver reads the pages as tabs,
      nothing clips at the largest text size.
- [ ] **D3. Show page, episode rows and the episode card** (L; split into D3a
      rows and show page, D3b card, if needed). Done when the `headerWash` (six
      themes), `rowMeta` and `ensureArtworkColor` (saves once, skips when set)
      tests pass, and on TestFlight a show is tinted on its first visit, rows
      have two trailing controls, "…" downloads, played rows are readable, and
      the card has one main button and the action strip.
- [ ] **D4. Discover, search and the Podcasts grid** (M). Done when the
      `isFollowLink` tests pass, a pasted RSS or Apple link follows the show
      from the search bar, hero cards snap, category tiles grow instead of
      clipping, and Podcasts and Discover use `EmptyState`.
- [ ] **D5. Up Next, Playlists, Profile and Stats** (M). Done when `check.sh`
      passes, grouped cards show separators in all six themes (Dark included),
      no header is uppercase, swipe buttons show icons, and every empty screen
      offers a next step.

## What I'd leave alone, and why

- **Upstream files, Books and the `global.css` tokens**, because of the fork
  rules and to keep upstream syncs clean. **Tabs, Up Next's drag mechanics,
  playback and data**: they work, and Mo chose Pocket Casts' structure, so only
  the look changes.
- **The insides of the transcript view, chapter list, sleep timer sheet,
  AdsFound, SpokenResults and the forms** (`ShowSettingsScreen`,
  `PlaylistEditor`, `ArrangeShows`): purpose-built, and D1 already gives the
  forms the native bar. The amber ad marks are a working colour.
- **`ArtworkColor.swift`**: `vivid()` in TypeScript is enough; a Swift change
  needs macOS CI.
- **Custom Liquid Glass in content** (`@expo/ui` `GlassEffectContainer`,
  `buttonStyle("glass")`): Apple warns against overuse, SwiftUI glass ignores
  the custom themes, and each item costs a native host view.

## Later (parked)

Swipe actions on episode rows matching the top of "…" (as Apple advises); "Play
latest" on the show page; a Now Playing card in Up Next; artwork dropping into
the Up Next tab (Pocket Casts); opening the show from the card; double-tap
artwork to star (Castro); undo after a long seek (Overcast); playlist colours
and icons (Overcast); simulator screenshots in Fork CI; `DragList`'s fixed 76 pt
rows clip at accessibility text sizes.

## Sources (patterns only)

- Apple, Adopting Liquid Glass (system bars, glass used sparingly, menu items
  that match swipe actions, title-case headers, accessibility settings):
  <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass>;
  HIG Motion:
  <https://developer.apple.com/design/human-interface-guidelines/motion>
- Pocket Casts:
  <https://blog.pocketcasts.com/2026/06/11/pocket-casts-meets-liquid-glass/>
  (mini player shrinking with the bar),
  <https://support.pocketcasts.com/knowledge-base/player-toolbar-ios/> (four
  shortcuts and "…"),
  <https://support.pocketcasts.com/article/playing-episodes-and-managing-your-queue-ios>,
  <https://www.macstories.net/reviews/pocket-casts-7-a-host-of-improvements-make-the-app-feel-brand-new/>
- Apple Podcasts in iOS 26: <https://www.macrumors.com/guide/ios-26-podcasts/>;
  the low contrast in its speed panel:
  <https://www.eliseomartelli.it/blog/2025-10-09-apple-how-is-this-legible/>
- Overcast:
  <https://www.trustedreviews.com/news/overcast-podcast-app-gets-a-gorgeous-and-much-needed-redesign-4220727>,
  <https://9to5mac.com/2024/07/16/overcast-rewrite-major-update/>. Castro:
  <https://www.iclarified.com/65861/castro-podcasts-app-gets-rebuilt-player-engine-cleaner-layout-apple-watch-app-more>.
  Snipd: <https://www.tapsmart.com/apps/review-snipd/>. Apple Music analysis
  (third party, an approximation: artwork gradient, 0.92 scale when paused):
  <https://blakecrosley.com/guides/design/apple-music>
