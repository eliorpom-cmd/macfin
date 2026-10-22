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
