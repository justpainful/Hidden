# Hidden

A private, native iOS media app built around the **Hidden Photos workflow**: browse,
rediscover, review, organize and shuffle the media in your Hidden album — while Apple Photos
stays the source of truth and nothing is ever duplicated or uploaded.

Think of it as Apple Photos rebuilt specifically for Hidden media, with a change-tracking
Inbox, a fast Review mode, rediscovery collections, private organization (tags, ratings,
app-favorites, pins, notes), viewing history, insights, and a seeded, weighted, no-repeat
Smart Shuffle engine.

- **Platform**: iPhone first, iOS 26.0+
- **Stack**: Swift, SwiftUI, PhotoKit, SwiftData, AVKit, LocalAuthentication, Swift Charts.
  No third-party dependencies.
- **Design**: native iOS 26 Liquid Glass (`glassEffect`, `GlassEffectContainer`) — glass for
  chrome only; media stays the hero.

## ⚠️ The one limitation you must know about

**Apple protects the system Hidden album independently of third-party apps.**

Since iOS 16, the Hidden album can require Face ID (Settings → Apps → Photos → "Use Face
ID"). While that protection is enabled, **PhotoKit returns no hidden assets to any
third-party app — including this one — even when hidden assets are explicitly requested.**

There is no supported API that lets an app authenticate and unlock Apple's Hidden album.
This app's own Face ID lock protects *the app*; it cannot and does not unlock Apple's Hidden
album. To use Hidden with your hidden media, the system protection for the Hidden album must
be turned off in Photos settings. The app detects the empty-fetch state and explains it
honestly rather than guessing which cause applies.

Related honesty rules baked into the data model:

- PhotoKit exposes no historical "hidden date" or "favorite date". The app records
  `firstObservedHiddenAt` / `firstObservedFavoriteAt` — when *it* first observed the state —
  and never labels them as anything else.
- An asset disappearing from the accessible set may mean unhidden, deleted, or protected;
  the Inbox says "no longer here" and does not pretend to know which.

## Privacy model

- No account, no network calls of the app's own, no analytics/ads/tracking SDKs. The only
  network activity is PhotoKit itself retrieving iCloud originals when *you* open one.
- The app stores a small local SwiftData database: asset identifiers, tags, notes, ratings,
  review state, viewing history, playback positions, collection rules, shuffle state,
  observation dates, snapshots. **Never media.** Deleting the app never deletes your photos.
- App lock (Face ID / passcode), configurable relock timeout, an opaque privacy cover in the
  app switcher, Incognito mode (no history written), blur-thumbnails mode, Read-Only mode
  (no PhotoKit writes at all) and No-Delete mode.

## Architecture

```
Hidden/
  App/            entry, environment, root navigation, lock & privacy cover
  Core/           pure logic (snapshot diffing)
  DesignSystem/   Palette, Typo/Space/Radius/Hit, Liquid Glass vocabulary, grid & tiles
  Models/         HiddenAsset (plain value), AssetMeta, filters & sorts (pure)
  Persistence/    SwiftData schema + MetadataStore facade
  Services/
    PhotoLibrary/ PhotoLibraryProviding + real PhotoKit impl + deterministic mock
    MediaLoading/ PHCachingImageManager-backed MediaProviding
    Authentication/ AppLockService
  Features/       Inbox, Library, Viewer, Review, Discover, Shuffle, Insights, Settings
HiddenTests/      pure-logic tests (shuffle, diff, query, store) incl. 20k-item scale tests
HiddenUITests/    the screenshot tour CI runs on a simulator
```

PhotoKit sits behind `PhotoLibraryProviding` / `MediaProviding`. The mock implementations
generate a deterministic seeded library (assets *and* thumbnails), which is what unit tests,
previews and CI screenshots run against — `simctl` cannot mark seeded media as hidden, so a
real simulator library can never exercise these flows.

## Building

Open `Hidden.xcodeproj` in Xcode 26+ and run. No signing is needed for the simulator.

CI (GitHub Actions, `macos` runners):

- **Build** — compiles the app for the iOS Simulator on every push/PR.
- **Tests** — runs the unit test suite.
- **UI Smoke** — boots a simulator, drives every surface with XCUITest against the mock
  library, and uploads a screenshot artifact per surface (default size, largest
  accessibility size, Arabic/RTL).
- **Unsigned IPA** — builds Release for the device SDK with signing off and uploads a
  proper `Payload/`-rooted `.ipa`. It is unsigned by design: it installs via a signing
  tool (Sideloadly, AltStore, etc.), and no certificate ever lives in CI.
- **Release (signed)** — manual; needs the secrets documented at the top of
  [release.yml](.github/workflows/release.yml).

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layers, data flow, protocols
- [docs/PHOTOKIT.md](docs/PHOTOKIT.md) — the Hidden-album limitation in detail
- [docs/PRIVACY.md](docs/PRIVACY.md) — what is stored, what never is
- [docs/SHUFFLE.md](docs/SHUFFLE.md) — the shuffle engine's guarantees
- [docs/CI.md](docs/CI.md) — the lanes and what each proves
