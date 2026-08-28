# Architecture

## Layers

1. **Plain values** — `HiddenAsset` (a snapshot of one PHAsset), `AssetMeta` (the app's own
   metadata for it), `LibraryFilter`/`LibrarySort`, `InboxDigest`. Everything downstream
   consumes these; nothing outside the service layer touches a live PhotoKit object.
2. **Pure logic** — `LibraryQuery` (filter + sort), `SnapshotDiff` (inbox arithmetic),
   `ShuffleEngine` (queue building), `DiscoverCollection.members`. Deterministic, seeded
   where random, and unit-tested at 20,000 items.
3. **Services** — `PhotoLibraryProviding` (auth, hidden fetch, write-backs, change
   generation) and `MediaProviding` (thumbnails, caching, player items), each with a real
   PhotoKit implementation and a deterministic mock. `AppLockService` wraps
   LocalAuthentication. `MetadataStore` is the single write path to SwiftData.
4. **Model hub** — `LibraryModel` owns the accessible asset list, runs refresh
   (fetch → diff → observation dates → snapshot), and exposes lookup dictionaries to views.
5. **Views** — one feature directory per surface. UI state lives in the views; persistent
   state lives behind the store.

## Refresh cycle

fetchHiddenAssets → SnapshotDiff.compare(previous snapshot) → write observation dates
(firstObservedHiddenAt / firstObservedFavoriteAt, only ever "now") → journal change events
(never on the baseline pass) → save a new snapshot only when the set changed → publish
assets + digest + meta to views.

## Mock mode

`-UITestMockLibrary` swaps both providers for seeded implementations and forces an
in-memory database. The mock generates the same assets and the same thumbnail pixels for a
given seed, which is what makes CI screenshots reproducible.
