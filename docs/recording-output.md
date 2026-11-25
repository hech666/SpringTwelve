# Recording output

New completed recordings are saved as `AxsSpringTwelve-<UUID>.mp3` in the real `/var/mobile/Documents/CallRecordings` directory on all jailbreak schemes. This user-data directory must not be passed through `jbroot()`. Installed executable/resource paths and preference paths retain their existing scheme handling.

The existing entitled capture helper still captures the two call directions as temporary CAF streams. These are processing inputs, not two completed recordings. They are kept under `.work` and never indexed by the recording browser. A dedicated MP3 mixer produces one final recording; after a successful helper exit and a decodable non-empty output check, both temporary streams are deleted. Failed encoding retains the capture inputs for recovery rather than deleting the only audio. No existing user recording is bulk-deleted or silently migrated by installation.

The phone browser's directory action uses the same shared directory function and opens Filza at that real path. Settings now contains only the three category links and their preference subpages; the old Settings recording/import actions are removed. The browser accepts current AxsSpringTwelve MP3 names and previous M4A/MP4 names when placed in this directory. It retains existing safe file-open checks.

Changing a filename extension is not audio conversion. MP3 output requires an actual encoder and must be decode-tested. Full call capture, audio quality, and access to the real directory from the user's jailbroken phone still require device validation.
