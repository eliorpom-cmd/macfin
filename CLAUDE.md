# Macfin

Native macOS app (SwiftUI, macOS 26+) that plays the movies and TV shows of a Jellyfin server and reports playback
progress so other Jellyfin clients resume at the same point.

Design: `DESIGN.md` is the reference for any interface change. Strings: `Macfin/Resources/Localizable.xcstrings`
(English development language, French translation).

## Architecture

- `Macfin/Jellyfin/JellyfinClient.swift`: minimal REST client. Sign-in, `/Items`, `/UserItems/Resume`,
  `/Items/Latest`, images, direct-play stream `/Videos/{id}/stream?static=true` (no transcoding),
  playback reports `/Sessions/Playing{,/Progress,/Stopped}`, Quick Connect approval.
- `Macfin/App/AppModel.swift`: global state (`AppModel.shared`), in-house navigation (`detail`), and
  `PlaybackSession`: AVPlayer plus a progress report every 10 s, on pause, on stop, and when the app quits.
- `Macfin/Views/`: `HomeView` (featured banner, rows, grid), `MovieDetailView`, `PlayerScreen`
  (QuickTime-style title bar and glass control bar), `LoginView`, `QuickConnectSheet`.
- `Macfin/Jellyfin/CredentialStore.swift`: session token in the keychain, service = bundle identifier.
- `Macfin/App/DemoAutomation.swift`: Debug-only hooks driven by environment variables, used by `scripts/screenshots.sh`.

## Decisions

- Default server `http://127.0.0.1:8096`. ATS: `NSAllowsLocalNetworking` (plain HTTP on the local network only).
- No `NavigationStack` (no transition on macOS, duplicate back button): the details page is an animated overlay.
- The player replaces the library instead of covering it; the library scroll position is kept in `AppModel.homeScroll`.
- Scrubbing preview uses Jellyfin trickplay images (enabled per library on the server).
- Player: bare `AVPlayerLayer` plus `AVPictureInPictureController`, custom 5-button bar, no volume control.
- Executable name stays ASCII (`Macfin`).
- Sandbox with `network.client` only, hardened runtime, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`.
- Signing: ad hoc by default (`Config/Signing.xcconfig`); a developer's team goes in the untracked `Config/Local.xcconfig`.

## Build

```bash
xcodegen generate
xcodebuild -project Macfin.xcodeproj -scheme Macfin -configuration Release -derivedDataPath build build | xcbeautify | tail -5
```

## Demo server and screenshots

```bash
scripts/demo-library.sh          # throwaway Jellyfin on port 8097 in .demo/, free movie excerpts, user demo/demo
scripts/screenshots.sh [en|fr]   # Debug build with bundle ID <app id>.demo, captures docs/screenshots/
scripts/demo-library.sh stop
```
