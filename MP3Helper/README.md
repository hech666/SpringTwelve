# Haoge SpringTwelve MP3 build component

The helper is built from the exact `RealtimeHelper` sources and linked against LAME 3.100 built from the pinned archive in `vendor/lame-3.100.tar.gz`.

- Build with `bash build-lame-macos.sh` on macOS with Xcode command-line tools and an iOS 16.5 SDK.
- The LGPL source archive and `LAME-COPYING` are included in the project and `LAME-COPYING` ships with the package.
- The helper is an executable launched only by the single SpringTwelve injection dylib; it is not a second tweak or dylib.
- User recordings remain under `/var/mobile/Documents/CallRecordings` and are never included in package artifacts.
