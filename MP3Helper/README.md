# SpringTwelve MP3 helper / LAME acknowledgement

AxsSpringTwelveMP3Mixer uses unmodified **LAME 3.100**, https://lame.sourceforge.io/ (also https://www.mp3dev.org/), under the GNU Library General Public License version 2 or later. See the complete `LAME-COPYING` license. LAME copyright notices and authors are in the included complete source archive. No LAME source modifications are applied.

The helper source (`main.m`) and accompanying build/relink scripts in this directory are also supplied under that same version-2-or-later license, without warranty. Modification, reverse engineering for debugging such modifications, and relinking for personal use are permitted under the license. This grant does not alter licenses of unrelated SpringTwelve modules.

## Installed relink materials

The package includes this directory at the scheme-resolved `/usr/share/SpringTwelve/MP3Relink`:

- complete, original `lame-3.100.tar.gz` (SHA256 `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`);
- actual unstripped arm64e helper object `AxsSpringTwelveMP3Mixer.o` from this build;
- statically linked `libmp3lame.a`, helper source, entitlements, full LGPL text and build/relink scripts.

On a Mac with Xcode and ldid, run `bash relink.sh /absolute/path/to/your/libmp3lame.a`. Omitting the argument uses the supplied library. The resulting `AxsSpringTwelveMP3Mixer-relinked` is not installed automatically. To rebuild the supplied LAME source in this installed directory, first `mkdir -p vendor; cp lame-3.100.tar.gz vendor/`, then provide `THEOS` with `sdks/iPhoneOS16.5.sdk` and run `bash build-lame-macos.sh`. For a modified source tree, extract/edit the source under `.build/lame-3.100` and adapt/remove the archive checksum gate only for your own modified source. Relink with `.build/arm64e/install/lib/libmp3lame.a`. Modified binaries require compatible Roothide signing/installation and an arm64e-capable Apple toolchain; no DRM or secret signing key is required by this helper.

## Recording contract

`AxsSpringTwelveMP3Mixer downstream.caf upstream.caf /absolute/output.mp3` reads each stream as Float32 PCM, downmixes each direction to one channel, encodes left/right as 96 kbps joint-stereo MP3, and zero-pads the shorter stream. Differing or unsupported sample rates are rejected, not silently resampled. It writes a same-directory hidden 0600 `.part.*`, flushes/tags/fsyncs/closes it, fully decodes it with AVAudioFile and checks sample rate/channel count/length bounds, then publishes with `renamex_np(RENAME_EXCL)`. Existing destinations are never overwritten. Failure never removes CAF inputs. The coordinator deletes CAFs only after successful exit and an independent positive output check.

Neither this build nor static/package verification proves real call capture, channel balance, headset behavior, Roothide sandbox/file access, or iOS runtime MP3 decoding; those require device tests. SIGKILL/crash may leave hidden partial files or CAF recovery inputs. There is no automatic recovery UI or cleanup of failed recordings. Only the final `.mp3` is a user-facing recording; the list keeps its existing short-lived private playback/share snapshot for safe anchored file access.
