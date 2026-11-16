# Spec: Storyteller Lofi (the fork's own part)

## Goal

Play the sounds of each scene quietly under an audiobook's narration (rain, a
fire, the sea, a crowd, a quiet room) without spoiling anything. A Mac scores
each book ahead of time from what has already been narrated. The phone plays
that score under the narrator.

This spec covers only the fork's own work. Upstream Storyteller (server, web,
reader, sync) is taken as given. See `FORK.md`.

## Users

- **Mo**, the only user for v1: listens to Storyteller read-aloud books on an
  iPhone (through TestFlight) and scores books on a Mac. Mo also wants to listen
  to podcasts in the same app, with the ads skipped.

## Features

Already built (each has a pass/fail check):

- The user can turn the sounds on or off, and set their volume and "how much is
  going on", from the player's toolbar button. Check: the panel shows the
  current place and kind ("Running tap") while a scored book plays.
- The user can hear the current scene's sounds under the narrator, changing
  calmly when the scene changes. Check: Redwood Prologue at 2:27 plays running
  water, ch5 at 18:35 a train, and ch6 at 30:19 a crowd.
- The user can read with the narration stopped and still hear the sounds of the
  page on screen. Check: turning pages in a scored book changes the scene.
- The user can hear rare one-off sounds (a knock, thunder) and short pauses at
  big scene changes, each switchable in Settings. Check: the toggles exist and
  take effect.
- The user can import the sounds folder from iCloud in Settings, and it resumes
  if interrupted. Check: Settings shows the count of imported sounds.
- The import keeps going after the user closes the app: iCloud downloads every
  file at once, and iOS lets the app finish copying in the background. Check: an
  import left with the app closed has moved on when the app opens again.
- The user can drop a book into `~/Storyteller Lofi/Books` (or list it in
  `Books/wanted.txt`), and the Mac scores it and puts the score in the book on
  the server. Check: `tracks/<book>.score.json` appears and the phone finds it.
- The user can see the sound credits. Check: "Sound credits" opens CREDITS.md.

v1, still to do:

- The user can run a sound check from the sounds panel: it plays about 6 spots
  already heard (no spoilers), or from the book's opening (the first chapter
  with sounds, or about the first 5 minutes) when the user is not far in, for 20
  s each and asks how each sounded. The answers can be shared as text. Check: on
  TestFlight it plays every spot, returns the narration to where it was, and
  "Share results" copies the answers.
- The user can clearly hear the sounds while the narrator talks, at default
  settings. Check: Mo hears the three Redwood test spots without touching the
  sliders.
- The user hears no bad recordings (drips for running water, room noise, sounds
  that come and go). Check: the fetch's reject list holds every recording Mo
  flags, and the app skips them.
- The user can listen to "The Strength of the Few" with its sounds. Check: its
  score exists on the server and plays on the phone.
- The user hears the right place most of the time. Check: the scorer's eval
  score on `Tools/atmosphere/eval/cases.jsonl` is recorded and does not drop.

Podcasts, planned (Mo's ask, approved 2026-11-16; design in
`docs/PODCASTS-PLAN.md`):

- The user can open Podcasts from a side menu on the Books screen, add a show by
  searching Apple's podcast directory or pasting an RSS link, and see its
  episodes. Check: a show added both ways lists its episodes.
- The user can play an episode with speed, skip buttons and the lock screen, and
  a book and a podcast never play at the same time. Check: switching between
  them on the phone plays only one.
- The user can add a show from an Apple Podcasts share link, and the shows they
  follow in Apple Podcasts appear in Storyteller by themselves (one way, through
  the Mac), with episodes finished there marked as played. Check: a show
  followed in Apple Podcasts appears within the hour.
- The user can download episodes (also with the app closed) and keep an Up Next
  list that carries on with the screen locked. Check: a downloaded episode plays
  in airplane mode, and the next one starts by itself.
- The phone transcribes each downloaded episode and finds its ads, with nothing
  sent off the phone and no paid service. Check: the episode shows "N ads found"
  and an "Ads found" list.
- The player skips those ads by itself, shows "Skipped ad" with Undo, and can be
  turned off per show. The hosts' own plugs (Patreon, merch) are skipped too,
  under their own switch. Check: on 3 episodes Mo picks, most ads (4 in 5) are
  skipped and at most one skip cuts the show.

## Out of scope (v1)

- Changing upstream code beyond the registered touch points (6 today; the
  podcasts plan adds one, on the Books screen).
- The shelved lofi music (`shelved/lofi-music/`).
- Publishing to the App Store or sharing builds with others.
- Android.
- Paid ad detection (Claude Haiku) and Apple's cloud model in the base podcasts
  version; ad skipping in streamed episodes.
- Scoring the whole server library (only chosen books).

## Assumptions

- The phone gets builds through TestFlight; the iPhone can't use Developer Mode.
- Scoring uses Claude through Mo's plan on the Mac (Opus).
- Podcasts are in English, and Apple Intelligence is on on the iPhone 15 Pro
  (iOS 26 or later).
- Recordings come from Freesound (personal edition) and Wikimedia Commons
  (publish edition) and are never committed.

## Open questions

- Are the sound levels from PR #27/#28 loud enough on the phone? Mo hasn't
  confirmed this on a build since 11.1.
- What eval score counts as "good enough" for matching?
