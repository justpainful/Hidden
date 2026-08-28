# Privacy

## Stored locally (SwiftData)

Asset identifiers, observation dates, viewing history (view counts, last viewed, shuffle
exposures, playback positions), review state, app-favorites, pins, ratings, tag names,
notes, video bookmarks, smart-collection rules, queues, library snapshots (identifier
lists), and an optional change journal. All of it lives in the app container on device.

## Never stored, never sent

- No copies of photos or videos. Thumbnails are memory-cache only.
- No network calls of the app's own. The only network activity is PhotoKit retrieving an
  iCloud original when the user opens it.
- No analytics, advertising or tracking SDKs. No account.

## Controls

App lock (Face ID/passcode) with configurable relock timeout and a manual Lock Now; an
opaque cover whenever the scene is inactive so the app switcher shows nothing; Incognito
(no history written); Clear Viewing History; Reset App Data; blur-thumbnails; Read-Only
mode (no PhotoKit writes); No-Delete mode (no delete control anywhere).
