# Test fixtures

`storyteller-reader/` is `libraries/StorytellerKit/Tests/iOS/Fixtures/reader.epub`
from the Storyteller monorepo (https://gitlab.com/storyteller-platform/storyteller,
commit 51cc2aa), unzipped. Storyteller is MIT licensed, Copyright (c) 2023 Shane Friedman.

`OEBPS/audio.wav` is replaced by an empty WAV (header only, no samples): the
text-side code reads only the OPF, SMIL and XHTML, so the 4 minutes of silence
in the original would only add 3.8 MB to the repository.
