# CI

All lanes run on GitHub Actions macOS runners with the newest installed Xcode selected
explicitly. `set -o pipefail` everywhere; failures are surfaced, not tailed away.

| Lane | Trigger | Proves |
| --- | --- | --- |
| Build | push, PR | the app compiles for the iOS Simulator |
| Tests | push, PR | the pure logic holds, including 20k-item scale tests |
| UI Smoke | push to main | every surface renders and survives; uploads screenshots (default, largest text size, Arabic/RTL) |
| Unsigned IPA | push to main, tags, manual | a device-SDK Release build packages into a valid unsigned .ipa artifact |
| Release | manual | signed archive, only with the documented secrets |

The UI tour runs against the deterministic mock library (`-UITestMockLibrary`) because
`simctl addmedia` cannot mark assets hidden — a real simulator library can never reach the
Hidden flows.
