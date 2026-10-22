# Macfin Design

> Black background, a large image of the featured movie at the top, rows of 16:9 images, then a grid of
> 2:3 posters. White text, one white capsule button per screen. The player fills the whole window.

- **Surface**: macOS app (SwiftUI, macOS 26+)
- **Origin**: modeled on Apple's TV app, dark appearance only
- **Token file**: `Macfin/DesignSystem/Tokens.swift`

## Principles

1. Always dark: `.preferredColorScheme(.dark)` on the window, `Tokens.Color.base` background.
2. Text comes in three tones: `text` (100%), `text2` (62%), `text3` (40%). Never a hard-coded gray.
3. One filled button per screen (`PrimaryButtonStyle`, white capsule); everything else uses `.glass`.
4. Images carry the screen: no frames, no borders, only corner radius and a shadow on hover.
5. Everything clickable grows by 4% on hover (`CardButtonStyle`).

## Colors

| Name | Value | Token | Role |
|---|---|---|---|
| Background | `#000000` | `Color.base` | window and player background |
| Surface | `#1C1C1E` | `Color.surface` | image placeholder while loading |
| Text | white 100% | `Color.text` | titles |
| Text 2 | white 62% | `Color.text2` | metadata, overview |
| Text 3 | white 40% | `Color.text3` | captions, time left |
| Hairline | white 8% | `Color.hairline` | bottom of the player title bar, preview border |
| Title veil | black 55% | `Color.titleBar` | player title bar background |
| Progress track | white 25% | `Color.track` | progress bar background |
| Action | white | `Color.action` | primary button, progress fill |
| On action | `#000000` | `Color.onAction` | primary button label |

## Typography

SF Pro (system font), no bundled fonts.

| Role | Style | Weight | Token |
|---|---|---|---|
| Featured title (no logo) | 56 pt | bold | `Font.hero` |
| Row title | `.title2` | bold | `Font.section` |
| Card title | `.callout` | medium | `Font.card` |
| Metadata | `.subheadline` | regular | `Font.meta` |
| Overview | `.body` | regular | `Font.body` |
| Caption | `.caption` | regular | `Font.caption` |

Overview limited to 560 pt wide, 3 lines in the featured banner.

## Space and layout

- **Gutter**: 48 pt left and right of each row
- **Between rows**: 40 pt
- **Between cards**: 20 pt (rows), 24 × 32 pt (grid)
- **Featured image**: 72% of the window height, under the toolbar
- **Poster**: adaptive width 168–226 pt, 2:3 ratio
- **Row image**: 340 pt wide, 16:9 ratio

## Shapes and depth

| Element | Corner radius | Shadow |
|---|---|---|
| Poster | 12 pt | on hover: black 50%, radius 16, y 10 |
| Row image | 14 pt | same shadow on hover |
| Primary button | capsule | none |
| Progress bar | capsule, 4 pt high | none |

## Motion

- **Hover / press**: `.snappy(duration: 0.22)`, scale 1.04 on hover, 0.97 on press
- **Image appearance**: `.easeOut(duration: 0.25)` fade
- **Player controls**: hidden after 2.5 s without mouse movement (except when paused), 0.25 s fade; the window buttons follow
- **Single transition** (`AnyTransition.page`): fade + scale 1.03 → 1, `.smooth(duration: 0.4)` (`Motion.page`), for every screen
  appearance: details, player (open and close), sign-in, featured banner. Never below 1, or the black background would show.
  The library stays underneath and keeps its scroll position.

## Components

### PrimaryButtonStyle
Primary action (Play, Resume). `action` capsule, `onAction` `.headline` label, 40 pt high,
22 pt horizontal padding, 0.85 opacity when pressed.
Code: `Macfin/DesignSystem/Components.swift`

### CardButtonStyle
Posters and row images. Hover scale and shadow above.
Code: `Macfin/DesignSystem/Components.swift`

### Player (modeled on QuickTime Player)
- **Title bar**: 28 pt `titleBar` veil (black 55%, `Size.titleBar`), `hairline` bottom border, centered 13 pt semibold `text2` title, window buttons; hidden in full screen.
- **Control bar**: 440 pt (`Size.controlBar`), `.glassEffect(.regular)`, 20 pt radius (`Radius.controlBar`), 24 pt from the bottom.
  Row 1: back to library, full screen | play/pause 22 pt | picture in picture, speed (0.5× to 2×), next episode (only for an episode that has one). 14 pt semibold icons.
  Row 2: elapsed time · white `.small` slider · time left, 11 pt tabular digits in `text2`.
- **Preview**: while hovering or dragging the slider, a 192 pt Jellyfin trickplay thumbnail (`Size.preview`), 8 pt radius, `hairline` border, time underneath, centered on the hovered point.
- **Speed**: popover listing 2× → 0.5×, checkmark on the current speed; the bar stays visible while the popover is open or the pointer is over the bar.
- Play/pause: the icon changes instantly, without animation.
- No volume control (the Mac's keys do that), no AVKit controls (a bare `AVPlayerLayer` surface drives picture in picture).
- Everything hides after 2.5 s of playback without movement, pointer included; always visible when paused.
- Keyboard: Space, ← → (±10 s), F, Esc (leaves full screen, otherwise goes back to the library).
Episode title: "Show — S1 · E2 · Title".
Code: `Macfin/Views/PlayerScreen.swift`

### Series page
Same banner as the movie details page; filled "Play / Resume S1 · E2" button (the episode in progress, otherwise the first unwatched one). Below: a "Season N" title, or a segmented picker when there are several seasons, then `EpisodeRow`: 280 pt 16:9 still (`Size.episodeStill`, `still` radius, progress and watched checkmark), "N. Title" in `.headline`, runtime in `text3`, 3-line summary in `text2`. The whole row is clickable and plays the episode.
Code: `Macfin/Views/SeriesDetailView.swift`

### Featured movie
Top banner, 72% of the height, hidden with the Featured toolbar button (`@AppStorage("showsHero")`).
Shows the progress (`ResumeProgress`) when the movie has been started.

### ProgressCapsule
Playback progress laid at the bottom of the row image, 12 pt inset. `track` background, `action` fill.

## Media and icons

- **Images**: from Jellyfin. `Backdrop` (featured), `Thumb` then `Backdrop` (rows), `Primary` (poster), `Logo` (featured title when available)
- **Icons**: SF Symbols, `.semibold` weight

## Avoid

- No accent color other than white.
- No border around images.
- Never more than one visible `PrimaryButtonStyle` button.
- No `NavigationStack`: on macOS it switches pages without a transition and adds its own back button.

## Tokens

The values above live in `Macfin/DesignSystem/Tokens.swift`. Change both in the same commit.
