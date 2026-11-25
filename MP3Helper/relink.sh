#!/bin/bash
# Run on macOS with Xcode. Optional argument: your rebuilt libmp3lame.a.
set -euo pipefail
cd "$(dirname "$0")"
LIB="${1:-libmp3lame.a}"
SDK="${SDKROOT:-$(xcrun --sdk iphoneos --show-sdk-path)}"
xcrun --sdk iphoneos clang -arch arm64e -isysroot "$SDK" -miphoneos-version-min=15.0 AxsSpringTwelveMP3Mixer.o "$LIB" -framework Foundation -framework AVFAudio -o AxsSpringTwelveMP3Mixer-relinked
ldid -Sentitlements.plist AxsSpringTwelveMP3Mixer-relinked
printf '%s\n' 'Relinked only; nothing installed. Preserve Roothide signing/install rules when replacing.'
