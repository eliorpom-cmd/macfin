# Contributing to Macfin

Bug reports, fixes, and translations are welcome. For a new feature, open an issue first so we can agree on the
idea before you write the code: Macfin stays small on purpose.

## Build

```bash
brew install xcodegen
xcodegen generate
open Macfin.xcodeproj
```

No Apple developer account is needed: builds are signed ad hoc unless you add `Config/Local.xcconfig`
(see `Config/Local.xcconfig.example`). `Macfin.xcodeproj` is generated and ignored by git, so edit `project.yml`
instead, then run `xcodegen generate` again.

To try the app without your own server, `scripts/demo-library.sh` starts a throwaway Jellyfin server on port 8097
with free movie excerpts (user `demo`, password `demo`). It needs `/Applications/Jellyfin.app` and `ffmpeg`.

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

## Design decisions

- Default server `http://127.0.0.1:8096`. ATS: `NSAllowsLocalNetworking` (plain HTTP on the local network only).
- No `NavigationStack` (no transition on macOS, duplicate back button): the details page is an animated overlay.
- The player replaces the library instead of covering it; the library scroll position is kept in `AppModel.homeScroll`.
- Scrubbing preview uses Jellyfin trickplay images (enabled per library on the server).
- Player: bare `AVPlayerLayer` plus `AVPictureInPictureController`, custom 5-button bar, no volume control.
- Executable name stays ASCII (`Macfin`).
- Sandbox with `network.client` only, hardened runtime, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`.
- Signing: ad hoc by default (`Config/Signing.xcconfig`); a developer's team goes in the untracked `Config/Local.xcconfig`.

## Guidelines

- **One topic per pull request.** A fix and a refactor go in two pull requests.
- **Interface**: read `DESIGN.md` first. Use the values in `Macfin/DesignSystem/Tokens.swift`, never hard-coded
  colors or sizes.
- **Text**: every user-facing string goes through `Localizable.xcstrings`, in English and French. English follows
  Apple’s style: Title Case for buttons and menu items, `…` for commands that open a window, no exclamation marks.
- **Code**: SwiftUI, Swift concurrency, comments in English. Keep the Jellyfin client minimal: add an endpoint only
  when a screen needs it.
- **Check before you push**: the Release build passes (`xcodebuild -scheme Macfin -configuration Release build`),
  and you tried the change against a real or demo server.

## Screenshots

If your change affects a screen shown in the README, refresh the screenshots:

```bash
scripts/demo-library.sh        # once: downloads the excerpts and sets up the demo server
scripts/screenshots.sh         # builds a Debug copy and captures docs/screenshots/*.png
scripts/demo-library.sh stop
```
