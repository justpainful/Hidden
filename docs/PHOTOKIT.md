# PhotoKit and the Hidden album

## What the app does

- Requests `.readWrite` authorization.
- Fetches `PHAssetCollection` smart album `.smartAlbumAllHidden` with
  `includeHiddenAssets = true` and snapshots each `PHAsset` into a plain value.
- Observes library changes via `PHPhotoLibraryChangeObserver` and refetches + rediffs
  (protection toggles do not itemise changes, so diffing against our own snapshot is the
  only reliable path).
- Write-backs are limited to supported change requests the user explicitly asked for:
  favorite, unhide, delete (each confirmed; delete affects Photos and iCloud Photos).

## The limitation

When the user enables authentication for the Hidden album (Settings → Apps → Photos), the
fetch above returns **zero assets**. No public API reports *why* a fetch is empty, so the
app carries an honest `hiddenEmpty` state: "either nothing is hidden, or the system
protection is on" — with instructions for both. There is no supported way to present Face
ID and unlock Apple's Hidden album from a third-party app, and this project does not use
private APIs, database scraping, or entitlement tricks to pretend otherwise.

## Dates

`PHAsset` exposes `creationDate` and `modificationDate` — there is no public added-date,
hidden-date or favorite-date history. The app therefore records observation times
(`firstSeenAt`, `firstObservedHiddenAt`, `firstObservedFavoriteAt`) and labels them as
observations everywhere they appear.
