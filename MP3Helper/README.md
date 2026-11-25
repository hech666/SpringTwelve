# SpringTwelve MP3 helper / LAME acknowledgement

AxsSpringTwelveMP3Mixer uses unmodified **LAME 3.100**, https://lame.sourceforge.io/ (also https://www.mp3dev.org/), under the GNU Library General Public License version 2 or later. See the complete `LAME-COPYING` license. LAME copyright notices and authors are in the included complete source archive. No LAME source modifications are applied.

The helper source (`main.m`) and accompanying build/relink scripts in this directory are also supplied under that same version-2-or-later license, without warranty. Modification, reverse engineering for debugging such modifications, and relinking for personal use are permitted under the license. This grant does not alter licenses of unrelated SpringTwelve modules.

## Distribution and relinking

The installed package carries only the required `LAME-COPYING` notice under `/usr/share/doc/SpringTwelve`. The full LAME source archive, this helper's exact unstripped arm64e object, the static archive, and relink/build scripts are deliberately distributed separately as the CI artifact `SpringTwelve-MP3Relink-<run>.zip` (also available from the matching source commit). This keeps non-runtime materials out of the device package while preserving the exact materials needed for relinking. See the complete `LAME-COPYING` license; LAME copyright notices and authors are in its source archive. No LAME source modifications are applied.

## Recording contract

`AxsSpringTwelveMP3Mixer downstream.caf upstream.caf /absolute/output.mp3` reads each stream as Float32 PCM, downmixes each direction to one channel, encodes left/right as 96 kbps joint-stereo MP3, and zero-pads the shorter stream. Differing or unsupported sample rates are rejected, not silently resampled. It writes a same-directory hidden 0600 `.part.*`, flushes/tags/fsyncs/closes it, fully decodes it with AVAudioFile and checks sample rate/channel count/length bounds, then publishes with `renamex_np(RENAME_EXCL)`. Existing destinations are never overwritten. Failure never removes CAF inputs. The coordinator deletes CAFs only after successful exit and an independent positive output check.

Neither this build nor static/package verification proves real call capture, channel balance, headset behavior, Roothide sandbox/file access, or iOS runtime MP3 decoding; those require device tests. SIGKILL/crash may leave hidden partial files or CAF recovery inputs. There is no automatic recovery UI or cleanup of failed recordings. Only the final `.mp3` is a user-facing recording; the list keeps its existing short-lived private playback/share snapshot for safe anchored file access.
