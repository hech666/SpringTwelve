# Recording separation (5.2.0-28 and later)

The SpringTwelve main package no longer contains automatic call recording, the recording browser, recording tab replacement hooks, MUtoolRecord/MUtoolMixer, LAME or MP3 encoding tools. The independent Phone tab hiding hooks, dual-SIM dialer and T9 remain.

Settings remain three real navigation pages: 电话设置 (4 switches), 禁用和隐藏 (12), 常规设置 (7). The four removed recording-only keys may remain in existing preferences but are no longer read or exposed by the package. No migration deletes or rewrites user audio files.

The recording baseline was preserved at commit 46c1cda (before removal) and separated for experimental standalone development. Its MP3 conversion has NOT passed device validation; the user reported conversion failure. The independent project must not be described as a working fix based on packaging alone.

Power-menu logs are now stored under /var/mobile/Library/Logs/SpringTwelve, no longer inside the user's old recording directory.
