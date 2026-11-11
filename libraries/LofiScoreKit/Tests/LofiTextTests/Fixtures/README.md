# Test fixtures

`storyteller-reader/` is `libraries/StorytellerKit/Tests/iOS/Fixtures/reader.epub`
from the Storyteller monorepo (https://gitlab.com/storyteller-platform/storyteller,
commit 51cc2aa), unzipped. Storyteller is MIT licensed, Copyright (c) 2023 Shane Friedman.

`OEBPS/audio.wav` (4 minutes of silence in the original) is left out on
purpose: the text-side code reads only the OPF, SMIL and XHTML and never opens
the audio the SMIL points at, and the fork's checks keep every audio file out
of this public repository. The OPF and SMIL still name it, as Storyteller's do.
