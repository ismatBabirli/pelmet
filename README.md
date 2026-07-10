<div align="center">

# Pelmet

**Hide the menu bar icons you rarely need — bring them back with one click or ⌥⌘B.**

*A pelmet is the board above a window that hides the curtain fittings.
This one hides your menu bar clutter, so nothing disappears behind the MacBook notch.*

<!-- Restore once CI is re-enabled (see .github/workflows/ci.yml.disabled):
[![CI](https://img.shields.io/github/actions/workflow/status/ismatBabirli/pelmet/ci.yml?branch=main&label=CI)](https://github.com/ismatBabirli/pelmet/actions/workflows/ci.yml)
-->
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

<!-- TODO(screenshot): add a short GIF of collapse/expand here once recorded, e.g. docs/demo.gif -->

</div>

> [!NOTE]
> **Status: working MVP.** Hide/show works today with zero special permissions.
> The notch-aware floating panel is on the [roadmap](#roadmap).

## Why

On notched MacBooks, macOS silently hides menu bar items that don't fit next to
the camera housing — no overflow indicator, the icons are just *gone*. Pelmet
gives you back control: park rarely-used icons behind a divider and summon them
when you need them.

## How it works — no private APIs, no permissions

Pelmet places two items in your menu bar:

```
[hidden icons…]  ╱  [always-visible icons…]  ‹  clock
                 │                           │
             separator                    toggle
```

- **⌘-drag** any menu bar icon to the **left** of the ╱ separator.
- When collapsed, Pelmet inflates the separator's width to ~10,000 pt, pushing
  everything left of it past the screen edge. Expand and they slide back.
- This is the same battle-tested technique used by Hidden Bar and Dozer. It
  needs **no** Screen Recording or Accessibility permission.

## Usage

| Action | How |
|---|---|
| Show/hide managed icons | Click the ‹ / › toggle, or press **⌥⌘B** |
| Choose which icons are managed | ⌘-drag them left of the ╱ divider |
| Settings (auto-rehide, launch at login) | Right-click the toggle → Settings… |
| Quit | Right-click the toggle → Quit Pelmet |

## Building from source

There are no packaged releases yet — building takes under a minute.

```bash
git clone https://github.com/ismatBabirli/pelmet.git
cd pelmet
swift run
```

The terminal prints a startup banner, the ‹/› toggle appears **next to the
clock**, and the ╱ divider starts at the left end of your icons. Nothing
showed up? See [Troubleshooting](#troubleshooting). Launch-at-login is the
one feature that needs a real .app bundle:

```bash
brew install xcodegen
xcodegen generate
open Pelmet.xcodeproj   # then build & run with ⌘R
```

### Troubleshooting

- **Nothing appeared in the menu bar.** On notched MacBooks, macOS silently
  hides menu bar items that don't fit — the very problem Pelmet exists to
  solve — and brand-new items are the first to be swallowed. Quit another
  menu bar app to free some space, then relaunch Pelmet.
- **Is it even running?** `swift run` prints a banner once the app is up, and
  pressing ⌥⌘B flips the chevron between ‹ and ›. No Dock icon or window is
  normal — Pelmet is a menu-bar-only app.
- **It quit when I closed the terminal.** Under `swift run` the app belongs to
  your terminal session; Ctrl-C (or closing the tab) quits it. Build the .app
  bundle above for a standalone install.
- **Don't run two copies at once.** Two instances fight over the same status
  items and saved positions. Quit the first one (right-click the chevron →
  Quit Pelmet, or Ctrl-C in its terminal).

## Roadmap

- [ ] **Notch panel** — a blurred, rounded panel below the notch that shows hidden icons live and forwards clicks (opt-in Screen Recording)
- [ ] Show on hover — reveal when the pointer touches the menu bar
- [ ] Profiles and per-item rules (e.g. "presentation mode")
- [ ] Custom hotkey recorder (replace the hardcoded ⌥⌘B)
- [ ] Notarized releases, Homebrew cask, Sparkle updates

The full vision and phased plan live in [PROJECT.md](PROJECT.md).

## Prior art

Pelmet stands on the shoulders of some excellent open-source projects:

- [Ice](https://github.com/jordanbaird/Ice) (MIT) — the most advanced open-source option; its "Ice Bar" panel is the reference for our notch panel
- [Hidden Bar](https://github.com/dwarvesf/hidden) (MIT) — origin of the expanding-spacer trick
- [Dozer](https://github.com/Mortennn/Dozer) (MIT)

## Contributing

Bug reports, ideas, and small PRs are very welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for a two-minute guide and a map of the
codebase.

## License

[MIT](LICENSE) © 2026 Ismat Babirli
