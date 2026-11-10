// When the music was shelved (November 2026), the clock, the scheduler, the gain and ramp
// maths, the output route, the stereo buffer, the loudness meter and the WAV writer moved
// out of the music targets into LofiAudioCore, which the atmosphere also uses. This
// re-export keeps every file in this module, and everything that imports it, compiling
// unchanged. See shelved/lofi-music/README.md.
@_exported import LofiAudioCore
