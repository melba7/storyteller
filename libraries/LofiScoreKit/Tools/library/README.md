# Choosing the music library

These scripts chose the tracks in `~/Storyteller Lofi/LofiMusic` on Mo's Mac. Only the
scripts and the choices live in git. The music never does, because the fork is public.

**Shelved on 10 November 2026.** Mo made ambience sounds the app's focus and set the
music aside for later. Nothing here is running. The [last section](#state-when-the-music-was-shelved)
says what state the library is in and where everything that is not in git lives.

Nobody listened to the candidates. Each track was measured, scored against every mood
from several weak sources of evidence, filtered hard for anything that would fight a
narrator, and then checked by eye on spectrograms. Treat the result as a strong first
draft that Mo's ears get the last word on.

## Pipeline

| Step | Script | Runs on | What it does |
|---|---|---|---|
| 1 | `build_candidates.py` | Mac (needs the network) | Downloads a pool of instrumental lofi from Free Music Archive and free-stock-music.com, one request a second. It reads each track's license on the track's own page and keeps only CC0, CC BY and CC BY-SA, skipping NC and ND. Writes `LofiCandidates/candidates.csv`, `skipped.csv`, the originals, and 64 kb/s analysis copies packed in `pack-*.tar`. |
| 2 | `analyze.py` | Linux or Mac, Python 3.13 with TensorFlow and librosa | Measures each track: loudness and loudness range, tempo, key and mode, brightness, busyness, speech-band energy, and YAMNet's frame-by-frame vocal curve, AudioSet mood classes and top classes. |
| 3 | `embed.py` | same | Computes YAMNet embeddings, for a small mood model trained on the site's mood tags. |
| 4 | `pick.py` | same | Scores every track for every mood, filters, ranks and picks. Writes `picks.csv`, `scored.csv` and `review.txt` (picks, alternates, and why each excluded track was left out). `overrides.csv` holds hand corrections. |
| 5 | `sheets_for_picks.py`, `sheet.py` | same | Draws one spectrogram sheet per mood with the vocal curve, to check the picks by eye. |
| 6 | `finalize.py` | anywhere with pandas | Writes `install.csv` (library file names, licenses, attribution) and `CREDITS.md`. |
| 7 | `install_library.py` | Mac (python3 and ffmpeg) | Copies the picks into a new library folder and checks each sha256. It measures loudness and true peak, then writes `library.json` and `SOURCES.csv`. |
| 8 | `make_samplers.py` | Mac | Makes one short listening sampler per mood: an excerpt of every track, levelled and crossfaded. |

YAMNet's code (`params.py`, `yamnet.py`, `features.py`, `yamnet_class_map.csv`) comes from
`tensorflow/models` under `research/audioset/yamnet`. The weights come from
`https://storage.googleapis.com/audioset/yamnet.h5`. Run every script with `python -I`, and
keep downloaded audio in its own folder away from the scripts.

## How a track is scored

Evidence for each mood, roughly on one scale:

- **tags**: free-stock-music.com's own mood tags.
- **title**: mood words in the title, and the mood words HoliznaCC0 puts in brackets.
- **album**: a hand-written prior for each Free Music Archive album.
- **genre**: the site's genres, weighted lightly.
- **model**: a logistic model on YAMNet embeddings, trained on the site tags. It is used only for moods where it cross-validates well (AUC at least 0.68).
- **sound**: where the track sits in valence and arousal, from tempo, mode, brightness and busyness, compared with each mood's anchor.
- **yam**: YAMNet's AudioSet mood classes (happy, sad, tender, exciting, scary and so on).

**Hard filters.** A track is left out for any of these:

- Vocals, whether frame by frame or mixed low throughout.
- A brief vocal sample, meaning a vocal peak over 0.35. One whisper under a narrator sounds like someone else talking.
- Shorter than 75 s or longer than 7 minutes.
- A loudness range over 15 LU.
- Little music in it.
- A holiday theme.
- A duplicate: the same title by the same artist, or near-identical audio.

**Ranking.** The ranking adds two scores:

- **Subtlety:** a steady level, little energy where speech lives, few onsets and a warm tone.
- **Quality:** bitrate, length and Free Music Archive favourites.

It takes a little off music with rain, birds or traffic recorded into it, because the atmosphere layer should add those only when the story has them. The busiest 2% of the pool is never picked.

**Filling the moods.** Moods are filled scarcest first, with these limits:

- At most 2 or 3 tracks per album (or per artist on free-stock-music.com), and 4 per artist.
- No two picks in a mood within 3 BPM in the same key.

A pick needs real evidence of its mood, from tags, title, album or the model, not just a matching sound.

## Solo piano for Somber, Melancholy and Mysterious

Mo listened to the lofi picks and found that lofi hip-hop does not carry sadness, and
that Mysterious missed too. Those three moods are now one piano and nothing else.

| Step | Script | What it does |
|---|---|---|
| 1 | `build_candidates.py fsm-piano fma-piano ia-musopen analysis pack` | Adds a piano pool tagged `phase:piano`: modern piano from the same two sites, and Musopen's public-domain recordings of Chopin, Bach, Schubert and Beethoven on archive.org. Later passes added Wikimedia Commons and other archive.org items. |
| 2 | `analyze.py`, then `instruments.py` and `sustain.py` | The usual measures, then two checks for "is it really one piano". `instruments.py` keeps how long each kind of instrument sounds. `sustain.py` looks for notes that swell or hold level, which a piano cannot do. |
| 3 | `pick_piano.py` with `overrides-piano.csv` | Scores, filters and picks 8 per mood. |
| 4 | `zoom_sheet.py`, `sheet.py` | Close-up spectrograms. A piano note is a sharp edge whose partials fade; a pad is a level line with no edge. |
| 5 | `finalize.py`, `install_library.py`, `make_samplers.py` | As before, plus the two changes below. |

**Telling solo piano apart.** The Musopen recordings are known to be one piano, so they
set the limits: on them YAMNet never hears ambient music or a synthesizer, and almost
never strings or drums. Modern stock "piano" tracks are a different matter. Most have a
pad or strings under the piano, and YAMNet hears most of them as plain "Music". A modern
track must pass the limits and then be seen to be one piano on a close-up sheet. Three
made it; the rest of the picks are classical.

**Mood for classical pieces** comes from `piano_pieces.py`, a table of what each piece
is like, keyed by form and opus number. Sound measures cannot tell a nocturne that
grieves from one that dreams, and nicknames mislead. Pieces with a loud middle section
are marked and ranked lower.

**Two changes to the files**, both made by `install_library.py` when `install.csv` asks
for them, and both recorded in `CREDITS.md` and `SOURCES.csv`:

- **Trim.** The player starts a track at its first sample. A classical recording often
  opens with one or two seconds of room silence, which would be a late start.
- **Even out.** A classical recording can swing 20 LU between its quietest and loudest
  passage, where a lofi track swings 6. Under a voice the quiet half vanishes and the
  loud half pokes out. The installer rides the gain slowly (7.5 s window, at most
  +10 dB), so notes keep their shape and whole passages move. The loudness range of the
  evened picks fell from 10-21 LU to 6-13 LU.

A changed track stays under its own license. The samplers for these moods play the
first 20 s of each track, since that is what the app plays first.

### Second pass, the same day

Mysterious was the weakest set: mostly Chopin, and one nocturne turned stormy after two
minutes. A second and third download pass (see the header of `build_candidates.py`)
brought Satie, Bach's Well-Tempered Clavier played by Kimiko Ishizaka (CC0) and more
modern piano, 35 candidates in all. Five tracks changed: Satie's Gnossiennes 1 and 4
went into Mysterious, the E-flat minor prelude BWV 853 and "Desolation" into Somber,
and Gymnopédie No. 1 into Melancholy. `overrides-piano.csv` names what left and why.

What that pass taught:

- **"Solo piano" in a description is not proof.** Four Satie recordings from one
  archive.org item are synthesizer versions. YAMNet heard piano in 0 to 1% of their
  frames and ambient music in up to half, and the close-up showed level bands with no
  attack. A recording from a trusted source now has to show piano in at least a quarter
  of its frames (`piano_f15`), and still gets its close-up.
- **Fugues open too quietly.** A fugue starts with one soft voice, and its first ten
  seconds sit 12 to 17 dB under the piece's own middle, even after evening out. The
  player starts every track at its beginning, so under a voice a fugue is a slow start.
  Preludes, the Gnossiennes and the Moonlight Sonata open at their full level.
- **Room noise hides a late start.** The trim treats 45 dB under the peak as silence.
  A home recording with an audible room never gets that quiet, so the Gnossiennes kept
  1.2 s of hiss before the first note. For such recordings the installer now takes the
  quietest 200 ms as the room and starts where the sound first stays 10 dB above it.
- **Wikimedia Commons needs a contact.** `upload.wikimedia.org` answered 429 after two
  files, also at one file every ten minutes. Its robot policy asks for a contact link
  or address in the User-Agent. That is Mo's to give, so the 43 other recordings chosen
  in `piano2_commons.json` (Gnossiennes 2, 3, 5 and 6, Debussy, Ravel, Brahms) are
  still unfetched.

## Re-running

```sh
# Mac: download or top up the pool (resumable)
python3 build_candidates.py

# Linux or Mac with the analysis stack, after copying candidates.csv and the packs over
python -I analyze.py OUT YAMNET --list paths.txt
python -I embed.py OUT/embed.npz YAMNET --list paths.txt
python -I pick.py candidates.csv OUT/features.csv OUT/yamnet PICKS OUT/embed.npz overrides.csv
python -I sheets_for_picks.py PICKS/picks.csv OUT/features.csv SHEETS
python -I finalize.py PICKS/picks.csv candidates.csv FINAL

# Mac: build the new library beside the old one, then swap folders by hand
python3 install_library.py FINAL/install.csv ~/Storyteller\ Lofi/LofiCandidates ~/Storyteller\ Lofi/LofiMusic-new
python3 make_samplers.py ~/Storyteller\ Lofi/LofiMusic-new ~/Storyteller\ Lofi/Renders/Mood\ samplers
```

For the piano moods:

```sh
python -I instruments.py OUT/instruments.jsonl YAMNET --list paths.txt
python -I sustain.py OUT/sustain.csv --list paths.txt
python -I pick_piano.py candidates.csv OUT/features.csv OUT/yamnet OUT/instruments.jsonl OUT/sustain.csv PIANO overrides-piano.csv
python -I zoom_sheet.py SHEETS/zoom.png candidates.csv ANALYSIS_COPIES c0811 c0817
# Join PIANO/picks.csv (mood, id, process) with the other moods' rows of PICKS/picks.csv, then finalize.py.

# Mac: build only the changed moods, move them in, then measure the whole library
python3 install_library.py FINAL/install.csv LofiCandidates LofiMusic-build --moods Somber,Melancholy,Mysterious --no-measure
#   mv the old mood folders to Retired/, mv the built ones into LofiMusic/
python3 install_library.py FINAL/install.csv LofiCandidates LofiMusic --measure-only
python3 make_samplers.py LofiMusic "Renders/Mood samplers" 20 1.0 Somber,Melancholy,Mysterious start
```

To swap a few tracks, put only their rows of `install.csv` into a small list and build
that into a side folder. Move the replaced files to `Retired/`, move the new ones in,
then run `--measure-only` with the full `install.csv` so `library.json` and
`SOURCES.csv` match the folders again.

`LofiMusic` also holds things other tools put there: the text side's model files
(`LofiMood-embed-*.json`), the atmosphere sounds, each book's mood track, and a section
at the end of `CREDITS.md`. So change mood folders in place rather than swapping the
whole folder, and keep that section when `CREDITS.md` is rewritten.

Two small diagnostics, both read-only: `noise_check.py` says how far a recording's
quietest stretches sit under its music, overall and above 4 kHz where hiss shows, and
`even_test.py` tries gain-riding settings on a file and reports the spread before and
after. The first decided that the Gnossiennes' room noise is no worse than what the
library already held; the second chose the evening-out settings.

## State when the music was shelved

**The library is complete and consistent.** `~/Storyteller Lofi/LofiMusic` holds 90
tracks, 8 per mood and 10 for calm, and `library.json`, `SOURCES.csv` and `CREDITS.md`
match the folders (checked on 10 November after the last change). The copy in iCloud
Drive, which the phone imports from, matched it the same day.

**What Mo has and has not heard.** Mo listened to samplers of the lofi library and
objected to three moods: Somber, Melancholy and Mysterious. Those became solo piano.
Samplers of both piano passes were sent, and the music was shelved before Mo said what
they think of them. So the piano sets are unreviewed, and the other eight moods passed
without comment rather than with praise.

**Loose ends, none of them blocking:**

- 43 recordings picked on Wikimedia Commons are not downloaded (Gnossiennes 2, 3, 5
  and 6, Debussy, Ravel, Brahms; `piano2_commons.json`). The site wants a contact link
  or address in the User-Agent. Mo was asked and the question was dropped with the
  shelving, so ask again before sending one.
- 16 tracks are CC BY-SA. For Mo's own phone that only means the credits. If the app is
  ever published, check how far share-alike reaches or swap them; every mood has CC0 or
  CC BY alternates in the pool (`review.txt`).
- Goldberg Variation 25 in Somber starts 0.85 s late. Its room is uneven, so the
  room-noise test in `install_library.py` leaves it alone. A sturdier estimate of the
  room, a low percentile in place of the quietest 200 ms, would catch it.
- Well-known pieces (Moonlight Sonata, Prelude in E minor) may pull a listener's
  attention. Alternates are in the piano `review.txt`.

**What is not in git, and where it is:**

| Where | What |
|---|---|
| Mac, `~/Storyteller Lofi/LofiMusic/` | The installed library. |
| Mac, `~/Storyteller Lofi/LofiCandidates/` | The pool: 996 originals, `candidates.csv`, the download state. Re-downloading it takes hours at one request a second. |
| Mac, `~/Storyteller Lofi/LofiMusic-tools/` | The scripts as they ran there, the install lists (`piano/round2/`), and a copy of the three analysis archives (`analysis/`). |
| Mac, `~/Storyteller Lofi/Retired/` | Earlier sets: the first 32 CC0 tracks, the lofi versions of the three piano moods, the five piano tracks the second pass replaced. |
| Mac, `~/Storyteller Lofi/Renders/Mood samplers/` | One sampler per mood and `What plays when.txt`. |
| Project files, `lofi-music-library/analysis/` | `music-library-analysis-996.tar.gz`: every measurement (YAMNet, librosa, instrument and sustain checks), the pick outputs with scores and reasons, and the install list. `music-library-sheets-lofi.tar.gz` and `music-library-sheets-piano.tar.gz`: the spectrogram sheets. The README beside them says how to re-pick without measuring anything again. |
| Project files, `lofi-music-library/selection*/`, `samplers*/` | The lists and samplers that were sent to Mo. |

**To pick the music up again:** unpack the analysis archives, change `overrides.csv` or
`overrides-piano.csv`, re-run the picker and `finalize.py`, then follow "Re-running"
above for the Mac side. New candidates need `build_candidates.py` on the Mac, an
analysis pack copied over, and `analyze.py` (with `instruments.py` and `sustain.py`
for piano) before they can be scored.
