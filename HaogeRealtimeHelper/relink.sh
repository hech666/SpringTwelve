#!/bin/bash
# Relink user-modified LGPL library with exact helper objects. Nothing installed.
set -euo pipefail
cd "$(dirname "$0")"
SDK=${SDKROOT:-$(xcrun --sdk iphoneos --show-sdk-path)}
xcrun --sdk iphoneos clang++ -arch arm64e -isysroot "$SDK" -miphoneos-version-min=15.0 HaogeCallRecorderRealtimeMain.o HaogeCallRecorderPCM.o "${1:-libmp3lame.a}" -framework Foundation -framework CoreFoundation -framework AVFAudio -framework AudioToolbox -o HaogeCallRecorderRealtime-relinked
ldid -Sentitlements.plist HaogeCallRecorderRealtime-relinked
