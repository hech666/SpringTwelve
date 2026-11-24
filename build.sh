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
make package THEOS_PACKAGE_SCHEME="$SCHEME" PACKAGE_VERSION="${PACKAGE_VERSION:-5.2.0}"
find packages -type f -name '*.deb' -print
