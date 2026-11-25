#!/bin/bash
# Build the unmodified, checksum-pinned LAME source with Apple's arm64e compiler.
set -euo pipefail
cd "$(dirname "$0")"
SDK="${SDKROOT:-${THEOS:?Set THEOS}/sdks/iPhoneOS16.5.sdk}"
export CC="$(xcrun --sdk iphoneos --find clang)"
export AR="$(xcrun --sdk iphoneos --find ar)"
export RANLIB="$(xcrun --sdk iphoneos --find ranlib)"
export CFLAGS="-arch arm64e -isysroot $SDK -miphoneos-version-min=15.0 -O2 -fno-common"
export LDFLAGS="-arch arm64e -isysroot $SDK -miphoneos-version-min=15.0"
python3 -c 'import hashlib,pathlib; p=pathlib.Path("vendor/lame-3.100.tar.gz"); assert hashlib.sha256(p.read_bytes()).hexdigest()=="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"'
mkdir -p .build
[ -d .build/lame-3.100 ] || tar -xzf vendor/lame-3.100.tar.gz -C .build
mkdir -p .build/arm64e
cd .build/arm64e
../lame-3.100/configure --build="$(../lame-3.100/config.guess)" --host=aarch64-apple-darwin --disable-shared --enable-static --disable-frontend --disable-decoder --disable-analyzer-hooks --disable-gtktest --prefix="$PWD/install"
make -C libmp3lame -j"$(sysctl -n hw.ncpu)"
make -C include install
make -C libmp3lame install
