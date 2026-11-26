#!/bin/sh
set -eu
cd "$(dirname "$0")"
SCHEME="${1:-roothide}"
case "$SCHEME" in
  roothide) ;;
  *) echo "Unsupported package scheme: $SCHEME" >&2; exit 2 ;;
esac
export THEOS_PACKAGE_SCHEME="$SCHEME"
export ARCHS="arm64e"
export HAOGE_CALLRECORDER_LAME_PREFIX="$(pwd)/MP3Helper/.build/arm64e/install"
python3 scripts/verify-preferences.py
python3 scripts/verify-haoge-recording.py
if [ ! -f MP3Helper/.build/arm64e/install/lib/libmp3lame.a ]; then
    bash MP3Helper/build-lame-macos.sh
fi
make clean DEBUG=0 FINALPACKAGE=1
# dm.pl can retain host numeric uid/gid even when it writes root/wheel names.
# Normalize archive ownership numerically; postinst separately reapplies setuid.
make package DEBUG=0 FINALPACKAGE=1 messages=yes THEOS_PACKAGE_SCHEME="$SCHEME" PACKAGE_VERSION="${PACKAGE_VERSION:-5.2.0}" _THEOS_PLATFORM_DPKG_DEB="$(pwd)/scripts/dpkg-deb-root" _THEOS_PLATFORM_DPKG_DEB_COMPRESSION=xz
find packages -type f -name '*.deb' -print
