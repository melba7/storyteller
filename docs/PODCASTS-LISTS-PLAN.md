# Podcasts: covers that fill their square, sharp covers, and many more lists

Plan by Fable for Mo's ask of 2026-11-18. Sonnet builds one milestone at a time,
Opus checks. All paths are under `applications/mobile/` unless they start with
`docs/`, `tools/` or `.github/`. Everything below stays inside fork-owned paths
(`podcasts/`, `modules/podcasts/`, `docs/`, `tools/fork/`,
`.github/workflows/`), so no new touch point is needed.

## 1. Findings

### 1.0 What could not be checked from the cloud

The cloud container's network policy refuses every host this work depends on.
`curl` got "CONNECT tunnel failed, response 403" from the proxy for
`rss.marketingtools.apple.com`, `itunes.apple.com`, `is1-ssl.mzstatic.com`,
`podcastcharts.byspotify.com`, `podcastindex.org`, `api.fyyd.de` and
`gpodder.net`. WebFetch failed too (Apple's `robots.txt` disallows it; the
others gave a server error). This is the same limit the earlier work hit
(`modules/podcasts/charts.test.ts:3-4`, `docs/PODCASTS-PLAN.md:147`). So the
facts about the remote addresses below come from the code, the saved fixtures
and what is publicly documented, and are marked **unverified** where no code
already depends on them. Milestone C0 checks them for real from a GitHub runner
(which has open internet) before anything is built on them. Mo can also allow
these hosts in the cloud environment's network settings, which would let the
builders use `curl` directly.

### 1.1 Covers that look too small for their square

Every cover in the section is drawn by one component, `podcasts/Artwork.tsx`. It
is already correct: the image is `width: "100%", height: "100%"` with
`contentFit="cover"` (`Artwork.tsx:36-41`) inside a square of exactly `size`
with `overflow-hidden` (`Artwork.tsx:25-31`). It has no padding and no inset,
and the placeholder icon is only drawn when there is no image. A non-square
picture is cropped to fill, not letterboxed. The 1 pt hairline border
(`Artwork.tsx:26`) is part of the frame, as in Apple's app.

So the frame itself is not the cause. Covers are drawn smaller than their box in
exactly two places, both on purpose:

1. **The featured cards on New: this is the bug Mo sees.**
   `podcasts/FeaturedCards.tsx:40-54` draws a wide 3:2 card filled with the
   cover's colour and puts the cover in the middle at only 72% of the card's
   height (`size={Math.round(height * 0.72)}`, line 51). On a 393 pt phone the
   card is about 337 x 225 pt and the cover is 162 pt, so more than half of the
   card is empty colour. Apple fills that card with wide editorial art that we
   don't have (`apple-reference/01-new-tab.png`), so the copy of the layout
   ended up as a small square in a big box.
2. **The episode page**, `podcasts/PodcastEpisode.tsx:34,159-163`: a 200 pt
   rounded cover centred on the colour header. This is Apple's own layout for an
   episode (`docs/PODCASTS-APPLE-DESIGN.md:117`) and reads as a cover on a
   background, not as a half-empty frame. It stays.

Everything else already fills its frame edge to edge: `ShowShelf.tsx:53-57`,
`UpNextCard.tsx:97-101`, `ShowHeader.tsx:172-176`, `PlayerArtwork.tsx:35`,
`MiniPlayer.tsx:76-80`, `EpisodeRow.tsx:187-191`, `LibraryShows.tsx:68,84`,
`ChartRow.tsx:31`, `CategoryChart.tsx:67`, `SearchShows.tsx:41`.

One thing the frame cannot fix: some shows ship artwork with a margin painted
into the picture itself (a logo on a white field, like Crime Junkie in
`apple-reference/01-new-tab.png`). Apple shows those the same way. Trimming
painted margins needs image analysis and is parked under "Later".

### 1.2 Blurry covers

What the app asks for today:

| Where the URL comes from     | Code                                                  | Pixels                                              | Biggest place it is drawn                                              |
| ---------------------------- | ----------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------- |
| Apple's overall chart        | `charts.ts:98` reads `artworkUrl100`                  | 100                                                 | 45%-wide shelf (177 to 198 pt), featured card, Home's "You Might Like" |
| Apple's category charts      | `charts.ts:105-118` takes the largest `im:image`      | 170                                                 | the same shelves, 60 pt chart rows                                     |
| Apple's search               | `directory.ts:20-30` takes the largest `artworkUrlNN` | 600                                                 | 60 pt rows (fine)                                                      |
| A followed or previewed show | `preview.ts:55`, saved by `dbFeeds.ts:129,188`        | the feed's own `itunes:image`, usually 1400 to 3000 | everything for followed shows (fine)                                   |

A 3x iPhone needs three pixels per point. A shelf tile 177 to 198 pt wide needs
about 530 to 600 pixels, and it gets 100 or 170. That is a three- to six-fold
upscale: this is the blur. It hits every chart-fed place: New's featured cards
and "Top Shows", the "For You" shelves, Home's "You Might Like", and the
category pages (60 pt rows need 180 pixels and the overall chart gives 100).

Followed shows are not affected: their `image_url` is the feed's own full-size
picture, and each refresh writes it again (`dbFeeds.ts:188`). No chart thumbnail
is ever stored in the `shows` table, because following always goes through the
feed (`preview.ts:47-62`).

Apple's image addresses end in a size segment, for example
`.../mza_123.jpg/100x100bb.png` in the overall chart and `.../170x170bb.png` in
the category charts (the hand-written fixtures in `modules/podcasts/fixtures/`
have the same shape). Publicly this segment is `{width}x{height}{fit}.{format}`:
the server renders any size up to the original, `bb` keeps the whole picture,
and `jpg`, `png` and `webp` are all served. Rewriting it to `640x640bb.jpg`
should return a 640-pixel JPEG. **Unverified from here** (host blocked): C0
checks it, and the design falls back to the original address if a rewritten one
fails to load.

Caching and scaling: `expo-image` (`~58.0.17`) is used with default props. Its
defaults keep downloaded files on disk and scale the decoded picture down to the
view's size, so a 3000-pixel feed image in a 30 pt mini player does not cost
3000-pixel memory, only download time. No prop in the app requests a size, so
nothing downscales a good source into a blurry one: the blur is only the small
source. (The builder should confirm these two defaults in the current expo-image
docs; `node_modules` is not installed in this container.)

### 1.3 The first page and its lists

The section opens on **Home**: it is the first trigger in
`app/(root)/podcasts/(tabs)/_layout.tsx:32`, and `lastTab.ts:20` says "Home at
first". Home (`podcasts/Home.tsx:88-125`) shows at most three shelves: "Up
Next", "Your Top Shows" (12) and "You Might Like" (12). With few followed shows
it is one screen tall, or just the empty state. Apple's Home is a long run of
shelves (`apple-reference/09-home-scrolled.png`).

New (`podcasts/DiscoverBrowse.tsx:73-140`) has the featured cards, "Top Shows"
(25 of 50), up to three "For You" shelves and the 19 category tiles.

Charts today (`modules/podcasts/charts.ts`): the overall chart from Apple's
marketing-tools feed (line 50), a category chart from the older iTunes RSS feed
(line 52), then one iTunes lookup call to turn Apple ids into feed links (line
53, 246). Each answer is kept 24 hours in the `cache` table (`CACHE_MS`, line
56); `cachePut` deletes rows older than 7 days (`cacheSql.ts:7`). Two weaknesses
matter for a longer page:

- An answer older than a day is thrown away before the new fetch succeeds
  (`charts.ts:236-240`), so with no network the chart is an error, not
  yesterday's list.
- Every chart costs one lookup call. Apple's search and lookup service is
  documented as limited to about 20 calls a minute. Twenty lists loaded at once
  would hit that.

Country: there is no country setting anywhere in the app. `us` is written into
the two addresses (`charts.ts:50,52`) and nowhere else.

### 1.4 Sources

| Source                                                                                                                                                                                | Key or cost                                         | State                                                                                                                        | Verdict                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Apple overall top shows: `rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json`                                                                                       | none                                                | already used and working in the shipped app                                                                                  | Use.                                                              |
| Apple top shows per genre: `itunes.apple.com/us/rss/toppodcasts/limit=50/genre=<id>/json`                                                                                             | none                                                | already used for 19 genres                                                                                                   | Use for all 19 as shelves.                                        |
| iTunes lookup: `itunes.apple.com/lookup?id=a,b,c`                                                                                                                                     | none; about 20 calls a minute, up to 200 ids a call | already used                                                                                                                 | Use, batched (one call for several lists).                        |
| Apple top episodes: `rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcast-episodes.json`                                                                                    | none                                                | **unverified** (address and whether a lookup of episode ids returns `feedUrl` and `episodeGuid`)                             | Use if C0 confirms; otherwise drop.                               |
| Apple sub-genre charts (the same genre feed with a sub-genre id such as Investing or Daily News; the id tree is at `itunes.apple.com/WebObjects/MZStoreServices.woa/ws/genres?id=26`) | none                                                | **unverified**                                                                                                               | Later: an easy way to add dozens more lists once the page exists. |
| Spotify charts: `podcastcharts.byspotify.com/api/charts/top?region=us` (also `trending` and `top_episodes`)                                                                           | none                                                | **unverified**; publicly it returns a JSON list with `showUri`, `showName`, `showPublisher`, `showImageUrl`, `chartRankMove` | Use if C0 confirms it answers a plain request, see below.         |
| Podcast Index                                                                                                                                                                         | free but needs a key and secret                     | not tested                                                                                                                   | No: keys can't live in a public repo.                             |
| gpodder.net top list (`gpodder.net/toplist/50.json`)                                                                                                                                  | none; gives feed links directly                     | blocked here                                                                                                                 | No: small, dated audience and an unreliable service.              |
| fyyd.de                                                                                                                                                                               | none                                                | blocked here                                                                                                                 | No: German-leaning catalogue.                                     |
| Chartable, Podtrac, Edison                                                                                                                                                            | no free API (Chartable closed in 2024)              | not tested                                                                                                                   | No.                                                               |

Spotify notes. It is the page's own data address, not a documented API, so it
has no published terms for this use, may want browser-like headers, and can
change or vanish. One call a day from a personal app is very low volume, and the
design lets the list disappear quietly when it fails. It gives no RSS link, so
each show has to be matched to a feed: first against the Apple chart shows
already in the cache (free), then by name through the iTunes search (rate
limited, so a few per day, remembered). Spotify exclusives have no feed and
never match. The app would show only the podcast's own cover (Apple's copy of
it, after the match), and the words "Top on Spotify"; no Spotify logo or
artwork. Mo named Spotify in the ask (see 5); the plan keeps it in its own late
milestones so that a dead address costs nothing.

## 2. Design decisions

### 2.1 Covers always fill their frame

- **Rule for the whole section:** a cover's frame is exactly the cover. The
  picture is cropped from its centre to fill a rounded square, with no colour
  box around a smaller picture. `Artwork` already does this, so the rule is kept
  by never wrapping it in a bigger box.
- **Featured cards (New) are redesigned** to the look Home's Up Next card
  already has, so the two tabs match:
  - The card is a square as wide as the old card (the window minus the gutter,
    the gap and the 28 pt peek, about 337 pt on a 393 pt phone), with 16 pt
    corners.
  - The cover fills the whole square edge to edge.
  - The lower 55% fades into the cover's own colour (`cardPalette`, as
    `UpNextCard.tsx:103-112` does), and the grey caps label ("TOP SHOW"), the
    title (two lines, bold) and the author (one line) sit on that fade in the
    palette's colours.
  - The label and title no longer sit above the card, so the row's total height
    stays about what it is today (about 337 pt against about 315 pt), and "Top
    Shows" does not move down the page.
  - While the colour is not measured yet the fade uses `HEADER_FALLBACK`.
- **Nothing else changes size.** Shelves, rows, the show header, the player, the
  mini player and the Up Next cards already fill their frames; they only get
  sharper pictures (2.2). The episode page keeps its 200 pt centred cover.
- New chart screens added below must use `Artwork` at the frame's own size.

### 2.2 One rule for sharp covers

A new pure module, `modules/podcasts/artworkSource.ts`, is the only place that
decides which picture address to load:

- **Input:** the stored address, the frame's size in points and the screen
  scale. **Output:** the list of addresses to try, best first.
- **Wanted pixels** = points times the scale (the scale capped at 3), rounded up
  to a bucket: **160, 320, 640 or 1280**. Four buckets keep the disk cache small
  and let screens share files: the shelf tile and the category row's zoom use
  the same 640 file.

  | Drawn at                                                          | Needs at 3x | Bucket |
  | ----------------------------------------------------------------- | ----------- | ------ |
  | 30 to 52 pt (mini player, queue rows)                             | 90 to 156   | 160    |
  | 56 to 96 pt (rows, episode rows)                                  | 168 to 288  | 320    |
  | 140 to 200 pt (shelves, grids, episode page)                      | 420 to 600  | 640    |
  | 300 pt and more (featured and Up Next cards, show header, player) | 900 to 1320 | 1280   |

- **Apple addresses** (host ends in `mzstatic.com` and the last path segment
  looks like `100x100bb.png`): the segment is rewritten to
  `<bucket>x<bucket>bb.jpg`. JPEG because a 640-pixel PNG of a photo is several
  times heavier. The original address is kept as the second choice.
- **Every other address** (feed hosts, the "Your files" tile, Spotify's image
  host) is returned unchanged: their sizes can't be rewritten.
- `Artwork` asks the rule with its `size` and `PixelRatio.get()`, loads the
  first address, and on a load error moves to the next one. So if Apple ever
  refuses a rewritten size the cover still shows, just softer, and the
  unverified rewrite can't blank a cover.
- `Artwork` also gets a 150 ms fade-in and a `recyclingKey` so that recycled
  list cells don't flash the previous cover. expo-image's disk cache and
  downscaling stay at their defaults. No new dependency.

**Shows already in the database:** nothing needs migrating. The `shows` table
only ever holds the feed's own full-size picture. The low-resolution addresses
live in the 24-hour chart cache and in memory, and the rule rewrites them at the
moment they are drawn, so cached charts become sharp the first time the new
build opens them. A followed show whose own feed picture is small stays as it
is; fetching Apple's copy for followed shows is under "Later".

### 2.3 Many more lists

**Where:** Home is the first page, so Home gets the lists, under its three
personal shelves. New gets the same lists in full (all 19 categories), so both
tabs scroll a long way. One planner decides both, so they can't drift apart.

**Home, top to bottom:**

1. Up Next (as now)
2. Your Top Shows (as now)
3. You Might Like (as now)
4. **Top Shows** (Apple's overall chart, ranked, 20 on the shelf)
5. **Top Episodes** (Apple's episode chart, 30, if C0 confirms the source)
6. **Top on Spotify** (ranked, up to 20, if C0 confirms and Mo agrees)
7. **Eight category charts**, each titled "Top in Comedy" and so on, ranked, 20
   on the shelf
8. **Browse Categories**: the existing grid of 19 colour tiles

An empty library keeps "No podcasts yet" at the top and still shows 4 to 8 under
it, so a new install's Home is full instead of blank.

**New, top to bottom:** featured cards, Top Shows, the "For You" shelves (as
now), Top Episodes, Top on Spotify, then **all 19 category charts**, then the
category tiles.

**How the categories are chosen and ordered** (pure, in `chartLists.ts`): first
the categories of the shows Mo follows, most common first (the existing
`pickForYou` counting, up to 4), then a fixed popularity order with those taken
out: News, Comedy, True Crime, Society & Culture, Business, Sports, Health &
Fitness, Technology, History, Science, TV & Film, Education, Arts, Kids &
Family, Fiction, Religion & Spirituality, Music, Leisure, Government. Home takes
the first eight, New takes all.

**Shelf style:**

- Show charts use the existing big `ShowShelf` (45%-wide square covers, rank in
  bold, title, author), as Apple's "Top Shows" does. The header's chevron opens
  the existing ranked "See All" page (`CategoryChart`) with all 50.
- Top Episodes uses a compact shelf: pages of three rows (a 60 pt cover, the
  rank, the episode title and the show's name), ten pages. A row opens the
  show's preview at that episode, as an episode search result does
  (`previewHref` with `guid` and `audio`). It has no "See All" page.
- Each shelf becomes a horizontal `FlatList` that draws only the tiles near the
  screen. About 14 shelves of 20 covers would otherwise load 280 pictures when
  Home opens.

**Loading:** each list has its own state. While it loads, its heading is drawn
with three grey rounded squares of the shelf's exact height, so the page has its
final length at once and does not jump. Lists appear from the top down.

**Fetching without hitting Apple's limit:** lists load in groups of three: the
three chart feeds at once, then **one** lookup call for all their ids (150 ids,
under the 200 limit), then the next group. Home's nine Apple lists cost three
lookups and New's twenty cost seven, well under 20 a minute, and only on the
first open of the day. A list being loaded by one tab is not fetched again by
the other (one in-flight promise per list).

**Caching and offline:**

- A list is fresh for 24 hours (the existing `CACHE_MS`) and is drawn straight
  from the cache with no request.
- An older kept list is **drawn at once** and replaced when the new answer
  arrives. If the fetch fails, the kept list stays. The cache table keeps rows
  for 7 days, so offline Home shows up to a week-old charts instead of nothing.
  Covers come from expo-image's disk cache.
- Pulling down on Home refreshes the feeds as now and also retries every list
  that failed or is older than a day.

**One source failing:** every list stands alone. A list that fails with nothing
kept is left out, heading and all, and the rest of the page is unaffected. Only
when every chart list fails with nothing kept does the page show one quiet line:
"Couldn't load the charts. Pull down to try again." Home's own three shelves
never depend on the network.

**De-duplication:**

- Inside a list: by Apple id (exists), and for Spotify by matched feed link.
- Across lists: ranked charts are left as the source ranks them, so a show can
  be number 1 overall and number 1 in News, as in Apple's app. Shows Mo follows
  stay in ranked charts too (the rank would lie otherwise); they stay filtered
  out of "You Might Like" and "For You" as now.
- The featured cards keep showing each show once.

**Country:** there is no setting today. The country becomes one constant,
`CHART_COUNTRY = "us"`, used by every address, so a setting can be added later
by changing one place. No settings UI now: Mo is in the US.

**Spotify matching** (only if it goes ahead): match each chart show by a
normalised title (lower case, no punctuation, no leading "the") and publisher,
first against all Apple chart shows in the cache (free), then through the iTunes
search for at most 10 unmatched shows a day, one at a time. Matches and misses
are remembered in one cache row that is written again each day. The shelf shows
the matched shows with their true Spotify rank (so ranks can skip numbers) and
Apple's copy of the cover. The list fills in over the first few days.

**Names and artwork:** list titles are plain text ("Top Shows", "Top Episodes",
"Top on Spotify", "Top in News"). No logos, no Apple or Spotify artwork, only
each podcast's own cover.

## 3. Milestones

Rules for every milestone: read `CLAUDE.md` first; test first; run
`tools/fork/check.sh --no-swift` (and `node tools/fork/check-fork.mjs`) before
calling it done; keep each file under about 300 lines; no new dependency; no
reference screenshot, key or audio in the repo; work on the `claude/*` branch
and never merge to `main` without Mo's OK. Screens can't be run in the cloud, so
a visual milestone is "done" when the checks pass and Fork CI's iOS build is
green; Mo confirms the look in TestFlight with the short list given in each
milestone.

**Build order and what can run side by side**

| Wave | Milestones                                           | Why they don't collide                                                         |
| ---- | ---------------------------------------------------- | ------------------------------------------------------------------------------ |
| 1    | C0, C1, C3, C4, C5, C6                               | each touches its own files                                                     |
| 2    | C2 (after C1), C7 (after C4, C5, C6)                 | `Artwork.tsx` only; Home and new files only                                    |
| 3    | C8 and C9 (both after C7; C9 also needs C0's answer) | C8 edits `DiscoverBrowse.tsx`; C9 edits `chartLists.ts` and `ChartShelves.tsx` |
| 4    | C10, then C11 (need C0's answer)                     | one after the other                                                            |
| 5    | C12                                                  | docs and the last check                                                        |

C1 to C3 alone fix Mo's two cover complaints, and C4 to C8 alone give the long
first page. C9 to C11 are extras that depend on what C0 finds.

### C0. Check the real addresses from a GitHub runner

- **What:** a small Node script, with no dependencies, fetches each address and
  prints what came back; a workflow runs it on GitHub (which has open internet)
  when the script changes on a `claude/**` branch. It answers the questions this
  plan could not:
  1. Do `.../100x100bb.png`, `.../640x640bb.jpg` and `.../1280x1280bb.jpg` of
     one chart cover each return 200, and what are their real pixel sizes (read
     from the PNG or JPEG header) and byte sizes?
  2. Does the top-episodes address answer, with which fields? Does a lookup of
     its episode ids return `feedUrl`, `episodeGuid` and `episodeUrl`?
  3. Do Spotify's `top`, `trending` and `top_episodes` addresses answer a plain
     request (and if not, with a browser-like `User-Agent`)? Which fields, how
     many entries?
  4. Do the overall chart with 100 entries and the genre tree address answer?
     The script prints each answer cut down to its first three entries into the
     job log between clear markers, to become test fixtures in C9 and C10.
- **Files:** `tools/fork/probe-podcast-sources.mjs`,
  `.github/workflows/podcast-sources-probe.yml`, and a "Sources checked" section
  in `docs/PODCASTS-PLAN.md` with the results.
- **Test first:** a vitest test is not useful for a network probe. Instead the
  script's header readers (PNG and JPEG width and height from the first bytes)
  are exported and tested in `tools/fork/` only if a test runner already covers
  that folder; otherwise check them by running the script against a local PNG
  and JPEG.
- **Done when:** the workflow has run once on the branch, its log shows a clear
  yes or no for each of the four questions, and the results are written into
  `docs/PODCASTS-PLAN.md`.
- **Risks:** Spotify may block GitHub's addresses while allowing a phone, so a
  "no" for Spotify is not final: say so and let Mo decide whether to try it on
  the phone. The workflow must have `permissions: contents: read` and must not
  run on `main` pushes (it would add noise, not a TestFlight build).

### C1. The rule that picks a sharp picture address (pure)

- **What:** `artworkSources(url, points, scale)` returns the addresses to try,
  best first, as in 2.2: buckets 160, 320, 640, 1280; Apple addresses rewritten
  to `<bucket>x<bucket>bb.jpg` with the original second; everything else
  unchanged; `null` and the "Your files" marker give an empty list or themselves
  untouched.
- **Files:** new `modules/podcasts/artworkSource.ts` and
  `modules/podcasts/artworkSource.test.ts`.
- **Test first:** a 177 pt tile at scale 3 with
  `https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/a/b/c/mza_1.jpg/100x100bb.png`
  gives `.../640x640bb.jpg` then the original. Also: 60 pt at 3 gives 320; 40 pt
  at 2 gives 160; 393 pt at 3 gives 1280 (never more); a scale of 0, NaN or 4 is
  treated as 1 to 3; `170x170bb.png` and `600x600bb.jpg` are recognised; a feed
  address, an `i.scdn.co` address, an Apple address without a size segment, and
  `LOCAL_ARTWORK` come back unchanged and alone; a malformed string does not
  throw.
- **Done when:** the tests pass and nothing else imports the module yet.
- **Risks:** an over-eager pattern rewriting a non-Apple address. The host check
  (`.mzstatic.com` as a suffix of the host, not a substring of the whole
  address) and the "unchanged" tests guard it.

### C2. `Artwork` uses the rule

- **What:** `Artwork` asks `artworkSources` with its `size` and
  `PixelRatio.get()`, loads the first address and, on a load error, the next. It
  adds a 150 ms fade-in and a `recyclingKey` of the stored address. The frame,
  the corners, the border and the placeholders stay as they are. No caller
  changes: every screen gets sharp covers through this one file.
- **Files:** `podcasts/Artwork.tsx` only (after C1).
- **Test first:** the behaviour that can be tested is C1's. Here, add one test
  to `artworkSource.test.ts` for a tiny pure helper if one is needed (for
  example `nextSource(sources, failedIndex)`); otherwise this is a visual
  milestone.
- **Done when:** checks pass; Fork CI's iOS build is green; the fallback resets
  when the `uri` prop changes (a recycled cell must not stay on its previous
  cell's fallback index). Mo's TestFlight check: New's "Top Shows" and a
  category page are sharp; with the phone offline, covers seen before still
  show.
- **Risks:** this file draws every cover in the section, including the player
  and the zoom transition target, so keep the change small. Confirm expo-image's
  current `onError`, `transition`, `recyclingKey` and default cache behaviour in
  its docs before using them. The first open after the update downloads the
  larger files once.

### C3. Featured cards filled by their cover

- **What:** the redesign in 2.1: a square card with the cover edge to edge, the
  lower part fading into the cover's colour, and the label, title and author on
  the fade. The paging, the peek of the next card, the press behaviour and the
  accessibility label stay.
- **Files:** `podcasts/FeaturedCards.tsx`; `modules/podcasts/featured.ts` and
  `featured.test.ts` for a small pure `featuredCardSize(windowWidth)` (the
  card's side: the window minus gutter 16, gap 12 and peek 28, never under 1).
- **Test first:** `featuredCardSize(393)` is 337, and a tiny or zero width
  gives 1.
- **Done when:** checks pass; no `Artwork` in the file is given a size smaller
  than the box it sits in; the text uses `cardPalette` colours so it is readable
  on light and dark covers; large text does not push the title out of the card
  (two lines for the title, one for the author, the rest cut). Mo's check: on
  New, each featured card is one big cover with its title on it, and nothing is
  a small square in a coloured box.
- **Risks:** `useArtworkColor` measures the colour from the stored address,
  which is the small one: fine for a colour. The card is about 20 pt taller than
  the old row; check "Top Shows" is still partly visible on a small phone.

### C4. Charts in groups, with yesterday's list as a fallback (pure)

- **What:** a group loader for many lists, as in 2.3.
  - `keptChart(id, deps)` gives the kept list and whether it is fresh (under 24
    hours), or null.
  - `loadChartGroups(ids, deps, onList)` reports each list through `onList`:
    first every kept list at once (fresh or not), then, for the lists that are
    missing or old, groups of three: three chart feeds at once, one lookup call
    for the ids whose feed link is not already known from the kept copy, the
    results saved and reported. A list whose fetch fails reports "failed" and
    keeps its old copy on screen; it never stops the other lists.
  - One in-flight promise per list id, so two tabs asking together fetch once.
  - `charts.ts` gets a single `CHART_COUNTRY = "us"` used by both addresses,
    exports what the group loader needs (the address builders, the parsers,
    `getJson`), and `loadChart` itself returns the kept old list when the fetch
    fails instead of throwing (it still throws when nothing is kept).
- **Files:** new `modules/podcasts/chartBatch.ts` and `chartBatch.test.ts`;
  small edits to `modules/podcasts/charts.ts` and `charts.test.ts`.
- **Test first:** with a fake `fetchFn` and cache: seven list ids with nothing
  kept make seven feed requests and exactly three lookup requests, and each
  lookup holds at most 150 ids; a fresh kept list makes no request; an old kept
  list is reported first and then replaced; when one feed answers 500 the other
  two lists of its group still arrive and the failed one reports "failed" with
  its old copy; when the lookup fails the whole group reports "failed" and the
  next group still runs; two overlapping calls for the same id fetch once;
  `loadChart` returns the old kept list when the fetch throws.
- **Done when:** the tests pass, the existing `charts.test.ts` still passes
  untouched except for the new fallback case, and cache keys are still
  `chart:<id>` in the same shape (so today's cached lists keep working).
- **Risks:** `charts.ts` is at 255 lines, so the new logic lives in the new
  file. A lookup address with 150 ids is about 1,700 characters, which is fine.
  Don't change the cache table or its 7-day pruning.

### C5. Which lists, in which order (pure)

- **What:** `planChartLists(followed, page)` returns the ordered lists for
  `"home"` or `"new"`: "Top Shows" (the overall chart), then the categories as
  "Top in <name>": followed categories first (reusing `pickForYou`'s counting,
  up to 4), then the fixed popularity order from 2.3 without repeats. Home gets
  the first eight categories, New all nineteen. Each list has an `id` (the chart
  id), a `title`, and `shelf` (how many to show: 20).
- **Files:** new `modules/podcasts/chartLists.ts` and `chartLists.test.ts`.
- **Test first:** nothing followed gives Top Shows, then News, Comedy, True
  Crime, Society & Culture, Business, Sports, Health & Fitness, Technology for
  Home; following two Science shows and one History show puts Science, then
  History, first and still gives eight categories with no repeat; "Your files"
  is ignored; New returns 1 + 19 lists; every category id is one of
  `CHART_CATEGORIES`.
- **Done when:** the tests pass.
- **Risks:** none beyond naming; keep the popularity order as a list of ids so a
  renamed category can't break it.

### C6. Shelves that draw only what is near the screen, and a loading shelf

- **What:** `ShowShelf` becomes a horizontal `FlatList` with the same tile,
  size, gap, gutters and snapping, drawing a few tiles at first and more as it
  scrolls. A new `ShelfSkeleton` draws three grey rounded squares with two grey
  bars under each, exactly as tall as a real shelf (with or without the rank
  line).
- **Files:** `podcasts/ShowShelf.tsx`, new `podcasts/ShelfSkeleton.tsx`.
- **Test first:** visual. If the tile height is computed, put it in a small pure
  function next to an existing look module and test that the skeleton and the
  shelf agree.
- **Done when:** checks pass; Home's "Your Top Shows" still zooms into the show
  page from a tile (`ZoomLink` inside the list); VoiceOver still reads rank,
  title and caption; the shelf's props are unchanged, so `Home.tsx` and
  `DiscoverBrowse.tsx` compile without edits.
- **Risks:** a horizontal `FlatList` inside the vertical page is fine, but it
  needs a fixed item length (`getItemLayout`) for the snapping to stay exact;
  the zoom transition's source view must still be the pressed tile.

### C7. Home gets the lists

- **What:** a hook, `useChartLists(lists)`, runs `loadChartGroups` and holds
  each list's state (loading, ready with its shows, or missing) and a `retry()`.
  A component, `ChartShelves`, draws for each planned list its `SectionHeader`
  (the chevron opens `categoryHref(id)`), then the skeleton or a ranked
  `ShowShelf` of the first 20; a missing list draws nothing; when every list is
  missing it draws the one quiet line from 2.3. `Home` adds `ChartShelves` for
  `planChartLists(shows, "home")` under "You Might Like", then "Browse
  Categories" with the existing `CategoryTiles`, and its pull to refresh also
  calls `retry()`. The empty state stays at the top when nothing is followed,
  without `flexGrow` pushing the lists off screen.
- **Files:** new `podcasts/useChartLists.ts` and `podcasts/ChartShelves.tsx`;
  `podcasts/Home.tsx`.
- **Test first:** the list logic is C4's and C5's. Add to `chartBatch.test.ts`
  any state reducer this hook needs (for example `applyListEvent(state, event)`:
  a "failed" event after "ready" keeps the shows; a "failed" event with nothing
  kept gives "missing").
- **Done when:** checks and the iOS build pass. Mo's check: Home scrolls through
  Top Shows and eight "Top in ..." shelves down to the category tiles; in
  aeroplane mode after one online open, the same shelves still show; a brand-new
  install shows the charts under "No podcasts yet"; tapping a tile opens the
  preview; tapping a heading opens the ranked page.
- **Risks:** `categoryHref` opens the page in the New tab's stack
  (`routes.ts:103-109`); that is existing behaviour for Home's links, so keep
  it. Home was 143 lines and must stay well under 300: the new parts live in
  `ChartShelves`. Do not start chart loading before the followed shows have
  loaded, or the category order would load twice.

### C8. New gets every category as a shelf

- **What:** on New, under the "For You" shelves, `ChartShelves` draws
  `planChartLists(shows, "new")` without its first entry (New already has its
  own "Top Shows" shelf) and without the categories already shown as "For You".
  The category tiles stay last. `CategoryTiles` moves to its own file to keep
  `DiscoverBrowse.tsx` small, and `Search.tsx`'s import follows.
- **Files:** `podcasts/DiscoverBrowse.tsx`, new `podcasts/CategoryTiles.tsx`,
  `podcasts/Search.tsx` (one import line); `modules/podcasts/chartLists.ts` and
  its test if the "leave these ids out" option is added there.
- **Test first:** `planChartLists` with an `omit` list leaves those ids out and
  keeps the order.
- **Done when:** checks and the iOS build pass. Mo's check: New scrolls through
  all categories; no category appears twice; the top of New loads as fast as
  before.
- **Risks:** New's first paint must not wait for 19 lists: the featured cards
  and "Top Shows" keep their own `useChart(TOP_CHART)` and the rest arrive in
  groups. Both tabs open together on a cold start; C4's shared in-flight promise
  keeps that to one fetch per list.

### C9. Top Episodes (only if C0 says the source works)

- **What:** `topEpisodes.ts` reads Apple's top-episodes answer and joins it to a
  lookup, giving for each episode its title, show name, cover, feed link and the
  guid or audio address. A compact `EpisodeChartShelf` draws pages of three
  ranked rows (60 pt cover). A row opens
  `previewHref(segments, feedUrl, { guid, audioUrl })`. The planner gets a "Top
  Episodes" entry after "Top Shows" on both pages, and `ChartShelves` draws that
  kind with the new shelf. Kept for 24 hours under `chart:top-episodes`, with
  the same old-copy fallback.
- **Files:** new `modules/podcasts/topEpisodes.ts` and `topEpisodes.test.ts`,
  new fixtures from C0's real answers (cut to a few entries, no personal data),
  new `podcasts/EpisodeChartShelf.tsx`; `modules/podcasts/chartLists.ts` and
  test; `podcasts/ChartShelves.tsx`; `chartBatch.ts` only if the loader needs a
  second kind.
- **Test first:** the real fixture parses to the expected entries in order; an
  episode whose lookup has no feed link is dropped; a wrong-shaped answer gives
  an empty list, not an error.
- **Done when:** checks and the iOS build pass. Mo's check: "Top Episodes" shows
  30 episodes in pages of three, and tapping one opens that show with the
  episode in view.
- **Risks:** if the lookup does not return feed links for episode ids, try one
  lookup of the shows' ids instead (the chart entry may carry the show's id) and
  open the preview without a target episode; if neither works, drop the
  milestone and say so. Do not guess the shape: use C0's saved answer.

### C10. Spotify's chart, read and matched (pure; needs C0's yes)

- **What:** `spotifyCharts.ts` reads Spotify's answer into rank, title and
  publisher; `matchKey` normalises a title;
  `matchSpotify(entries, known, remembered)` pairs each entry with a known Apple
  show (same normalised title, and the publisher and author agree when both
  exist) or a remembered match, and returns the matched shows with their Spotify
  ranks plus the entries still to look up, at most 10.
- **Files:** new `modules/podcasts/spotifyCharts.ts`, `spotifyCharts.test.ts`,
  and a fixture from C0.
- **Test first:** the real fixture parses in order; "The Daily" matches "the
  daily"; two different shows with the same title are told apart by publisher,
  and an unclear case is left unmatched rather than guessed; a remembered miss
  is not asked again; no more than 10 are returned to look up; the same feed
  never appears twice.
- **Done when:** the tests pass.
- **Risks:** a wrong match opens the wrong show, so prefer no match over a
  doubtful one. Spotify's field names must come from C0's saved answer.

### C11. "Top on Spotify" on the page (after C10 and C7)

- **What:** a loader fetches the chart once a day, matches against the Apple
  lists in the cache, looks up at most 10 unmatched shows through the existing
  `searchDirectory` one at a time, remembers matches and misses in one cache row
  (`spotify:matches`, written again each day so the weekly pruning keeps it),
  and keeps the finished list under `chart:spotify`. The planner adds "Top on
  Spotify" after "Top Episodes"; the shelf is the ranked `ShowShelf` with
  Apple's cover; "See All" reuses the ranked `CategoryChart` page, which learns
  the title for this id and shows each show's own Spotify rank.
- **Files:** new `modules/podcasts/spotifyLoad.ts` and `spotifyLoad.test.ts`;
  `modules/podcasts/chartLists.ts` and test; `podcasts/useChartLists.ts`,
  `podcasts/ChartShelves.tsx`, `podcasts/CategoryChart.tsx`.
- **Test first:** with fakes: a day-old list is served without a request; a
  failing Spotify address gives the kept list, or "missing" with nothing kept;
  at most 10 searches run and they run one after another; a search that fails is
  not remembered as a miss.
- **Done when:** checks and the iOS build pass. Mo's check: "Top on Spotify"
  appears with ranks; with the address unreachable, the shelf is simply absent
  and the rest of Home is unchanged.
- **Risks:** the address is undocumented and can change without notice: the
  whole feature must fail silently. No Spotify logo, colour or artwork, and no
  Spotify image host in the app. Keep the 10-a-day search limit, since the same
  Apple service serves the app's own search.

### C12. Docs and the last check

- **What:** update `docs/PODCASTS-APPLE-DESIGN.md` (featured card, the cover
  rule, Home's and New's lists) and `docs/PODCASTS-PLAN.md` (milestones C0 to
  C11 ticked, sources checked, "Later"); add any lesson to `docs/LESSONS.md`.
  Then Opus checks the whole diff against this plan and Mo's request. Mo's
  standing OK covers the merge once the check's findings are fixed and CI is
  green; the TestFlight build follows.
- **Files:** the three docs.
- **Done when:** `tools/fork/check.sh --no-swift` and Fork CI are green, and
  Opus's findings are fixed or listed.

## 4. Later (not in this round)

- Trimming margins that are painted into a show's own artwork.
- Apple's copy of the cover for followed shows whose feed picture is small or
  very large (it would also cut the download for 3000-pixel feed pictures).
- Sub-genre charts (Investing, Daily News and so on) as more lists.
- A country setting (the constant from C4 is the hook for it).
- Spotify's trending and category charts, if C11 works well.

## 5. Decisions taken

1. **Spotify:** Mo asked for lists "on Spotify, Apple Podcasts" by name, so C10
   and C11 go ahead if C0 shows the address answers. The shelf disappears
   quietly whenever the address fails or changes.
2. **Network in the cloud:** the hosts stay blocked in the cloud container; C0's
   GitHub run checks the addresses instead. The probe prints each answer, cut
   down to its first three entries, into the job log between clear markers (not
   as an artifact), so the builders can copy fixtures from the log.
3. **Merging:** Mo's standing OK covers merging the Podcasts pull request once
   it is checked and green; this round goes out as one TestFlight build.
