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
python3 scripts/verify-preferences.py
if [ ! -f MP3Helper/.build/arm64e/install/lib/libmp3lame.a ]; then
    bash MP3Helper/build-lame-macos.sh
fi
make clean
rm -rf artifacts/MP3Relink
mkdir -p artifacts
# dm.pl can retain host numeric uid/gid even when it writes root/wheel names.
# Normalize archive ownership numerically; postinst separately reapplies setuid.
make package THEOS_PACKAGE_SCHEME="$SCHEME" PACKAGE_VERSION="${PACKAGE_VERSION:-5.2.0}" _THEOS_PLATFORM_DPKG_DEB="$(pwd)/scripts/dpkg-deb-root" _THEOS_PLATFORM_DPKG_DEB_COMPRESSION=xz
find packages -type f -name '*.deb' -print
