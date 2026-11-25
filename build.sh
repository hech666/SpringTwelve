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
make clean
# dm.pl can retain host numeric uid/gid even when it writes root/wheel names.
# Normalize archive ownership numerically; postinst separately reapplies setuid.
make package THEOS_PACKAGE_SCHEME="$SCHEME" PACKAGE_VERSION="${PACKAGE_VERSION:-5.2.0}" _THEOS_PLATFORM_DPKG_DEB="$(pwd)/scripts/dpkg-deb-root"
find packages -type f -name '*.deb' -print
