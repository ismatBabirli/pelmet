<div align="center">

<img src="Resources/pelmet-icon.png" alt="Pelmet" width="168" height="168">

# Pelmet

**Hide the menu bar icons you rarely need — bring them back with a shortcut you choose (⌥⌘B by default) or pointer-safe one-click access.**

*A pelmet is the board above a window that hides the curtain fittings.
This one hides your menu bar clutter, so nothing disappears behind the MacBook notch.*

[![CI](https://img.shields.io/github/actions/workflow/status/ismatBabirli/pelmet/ci.yml?branch=main&label=CI)](https://github.com/ismatBabirli/pelmet/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ismatBabirli/pelmet?label=release&sort=semver)](https://github.com/ismatBabirli/pelmet/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Website](https://img.shields.io/badge/website-pelmet.xyz-C8A272)](https://pelmet.xyz)

<img src="Resources/pelmet-shelf.png" width="450"
     alt="Pelmet showing +4 beside its chevron and a frosted Shelf listing Screen Studio, ChatGPT, Docker Desktop, and Wispr Flow as four menu bar items hidden by the MacBook notch.">

**[pelmet.xyz](https://pelmet.xyz)** &nbsp;·&nbsp; [Download](https://pelmet.xyz/download) &nbsp;·&nbsp; [Guides](https://pelmet.xyz/guides) &nbsp;·&nbsp; [FAQ](https://pelmet.xyz/faq)

</div>

> [!NOTE]
> **Status: shipping.** Hide/show works with zero special permissions, and the
> notch-aware Shelf panel, software-island support, opt-in one-click access, and opt-in show-on-hover
> have shipped. One-click access uses advertised macOS Accessibility actions
> only and never creates mouse events or moves the pointer.

## Why

On notched MacBooks, macOS silently hides menu bar items that don't fit next to
the camera housing — no overflow indicator, the icons are just *gone*. Pelmet
gives you back control: park rarely-used icons behind a divider and summon them
when you need them. And when icons *still* don't fit, Pelmet is the only tool
that tells you: a small **+3** appears above its chevron, with tips one
right-click away. No other utility detects this, and Pelmet does it with zero
permissions.

Pelmet also recognizes software-drawn islands on displays without a physical
notch. Vibe Island has a built-in compatibility profile. Other persistent,
top-center accessory windows are detected locally and can be enabled and
calibrated in Settings. Pelmet models the resting width for coverage detection,
so hover expansion does not make the covered-icon count jump.

## How it works — no private APIs, no permissions

Pelmet places two items in your menu bar:

```
[hidden icons…]  ╱  [always-visible icons…]  ‹  clock
                 │                           │
             separator                    toggle
```

- Pelmet hides everything to the **left** of the ╱ separator — **⌘-drag** the
  icons you always want visible to its **right**, next to the clock.
- When collapsed, Pelmet inflates the separator's width (bounded at ~4,000 pt —
  macOS caps status-item windows near 5,000 pt), pushing everything left of it
  past the screen edge. Expand and they slide back.
- This is the same battle-tested technique used by Hidden Bar and Dozer. It
  needs **no** Screen Recording or Accessibility permission.
- If the expanded icons don't all fit beside the notch, the toggle shows a
  compact count above its chevron instead of letting them vanish without a trace.
  Right-click it for ways to make room. Detection uses only public
  window-geometry metadata. Software-island detection uses the same public
  metadata, with unknown apps disabled until you opt in. Nothing prompts for permissions or lights
  the screen-recording indicator.

## Privacy

Pelmet needs zero special permissions, has no accounts, and embeds no tracking
SDKs. It makes two kinds of network calls, both under your control:

- **Update checks** (Sparkle): asks you once before enabling checks every 6 hours.
  If a scheduled check meets a temporary network failure, Pelmet performs at
  most three recovery checks and shows the retry state in Settings. An **↑** in
  the menu bar means an update is ready to review; Pelmet never installs it
  without your approval.
- **Anonymous usage ping**: one tiny event per day (app version, macOS version,
  chip type, which Pelmet features are on) so we know how many people use Pelmet
  and what to prioritize. No personal data, no menu bar contents, never anything
  about the other apps you run, including software-island candidates; IP addresses are discarded on arrival. An in-app
  notice appears before the first ping is ever sent. Turn it off in Settings,
  with `defaults write com.ismatbabirli.Pelmet telemetryEnabled -bool NO`, or
  with `DO_NOT_TRACK=1`.

Every field is documented in [docs/TELEMETRY.md](docs/TELEMETRY.md), the sending
code is one small file, and the aggregate numbers are public. Crash reports never
leave your Mac: after a crash, Pelmet offers to open a prefilled GitHub issue
that you review and submit yourself.

## Usage

| Action | How |
|---|---|
| Show/hide managed icons | Click the ‹ / › toggle, or press **⌥⌘B** |
| Change either shortcut | Settings → General → **Shortcuts**: click one and type the new keys (⌫ removes it) |
| Reveal managed icons on hover | Enable **Show hidden items on hover** in Settings, then move the pointer into the menu bar |
| Keep an icon always visible | ⌘-drag it to the **right** of the ╱ divider |
| See why icons are missing | Hover or right-click the toggle when it shows **+N** |
| Lost the divider? | Right-click the toggle → Reset Divider Position |
| Fit more icons beside the notch | Settings → Make Room… (incl. tighter icon spacing) |
| Settings (hover, auto-rehide, launch at login) | Right-click the toggle → Settings… |
| Quit | Right-click the toggle → Quit Pelmet |

## Install

### Homebrew (recommended)

```bash
brew install --cask ismatBabirli/pelmet/pelmet
```

This taps `ismatBabirli/homebrew-pelmet` and installs the signed, notarized app
into `/Applications`. Upgrade later with `brew upgrade --cask pelmet`.

### Direct download

Download the latest `Pelmet-<version>.dmg` from the
[Releases page](https://github.com/ismatBabirli/pelmet/releases/latest), open it,
and drag **Pelmet** to Applications. Builds are signed and notarized by Apple, so
they launch with no Gatekeeper warning.

Pelmet is menu-bar-only — after launching, look **next to the clock**, not in the
Dock.

## Building from source

Prefer to build it yourself? It takes under a minute.

```bash
git clone https://github.com/ismatBabirli/pelmet.git
cd pelmet
swift run
```

The terminal prints a startup banner, and both the ‹/› toggle and the ╱
divider appear **next to the clock** — always visible, never behind the
notch. Building needs a Swift 6 toolchain (Xcode 16+ or recent Command Line
Tools); the app itself runs on macOS 13+. Launch-at-login is the one feature
that needs a real .app bundle:

```bash
brew install xcodegen
xcodegen generate
open Pelmet.xcodeproj   # then build & run with ⌘R
```

### Troubleshooting

- **Nothing appeared in the menu bar.** Pelmet's toggle and divider are
  seeded right next to the clock, the last spot macOS swallows, so this
  should be rare. If your bar is packed edge to edge, quit another menu bar
  app to free some space, then relaunch Pelmet.
- **A number like +3 sits next to the chevron.** That many icons don't fit
  beside the notch, so macOS is hiding them (it never says so itself).
  Right-click the chevron for tips: ⌘-drag important icons toward the clock,
  hide expendable ones behind ╱, or quit unused menu bar apps.
- **I can't find the ╱ divider.** Right-click the chevron → Reset Divider
  Position brings it back next to the toggle.
- **Is it even running?** `swift run` prints a banner once the app is up, and
  pressing ⌥⌘B (the default toggle shortcut) flips the chevron between ‹ and ›. No Dock icon or window is
  normal — Pelmet is a menu-bar-only app.
- **It quit when I closed the terminal.** Under `swift run` the app belongs to
  your terminal session; Ctrl-C (or closing the tab) quits it. Build the .app
  bundle above for a standalone install.
- **Don't run two copies at once.** Two instances fight over the same status
  items and saved positions. Quit the first one (right-click the chevron →
  Quit Pelmet, or Ctrl-C in its terminal).

## Roadmap

- [x] **The Shelf** — a blurred, rounded panel below the notch listing the icons macOS hid, opened by clicking the count (or ⌥⌘N by default). Rows show each item's app icon and name — **never a screen capture**, so no Screen Recording permission and no purple recording dot.
- [x] **Pointer-safe one-click access** — an *opt-in* Accessibility toggle that opens compatible hidden items using actions they advertise to macOS (and identifies them on macOS 26 Tahoe). It never posts mouse events or moves the pointer. Off by default; everything else works without it.
- [x] Show on hover: reveal when the pointer touches the menu bar (opt-in)
- [ ] Per-item rules and presentation mode (e.g. "always hide" or "hide sensitive items")
- [x] **Custom shortcut recorder** — record your own combination for hide-and-show and for the Shelf, or clear either one. Pelmet refuses combinations macOS owns (including ones you remapped) and reports when another app already claimed one. Labels follow your keyboard layout.
- [x] **Notarized releases + Homebrew cask** — a signed, notarized `.dmg` on every tagged release; `brew install --cask ismatBabirli/pelmet/pelmet`
- [x] **Reliable Sparkle updates** — opt-in checks every 6 hours, bounded retry after temporary network failures, an **↑** menu-bar reminder, EdDSA-signed downloads, and explicit approval before Install and Relaunch

The full vision and phased plan live in [PROJECT.md](PROJECT.md); release history
is in [CHANGELOG.md](CHANGELOG.md).

## Prior art

Pelmet stands on the shoulders of some excellent open-source projects:

- [Ice](https://github.com/jordanbaird/Ice) (GPL-3.0) — the most advanced open-source option; its "Ice Bar" panel is the behavior reference for our notch panel (GPL — we reference behavior, never code)
- [Hidden Bar](https://github.com/dwarvesf/hidden) (MIT) — origin of the expanding-spacer trick
- [Dozer](https://github.com/Mortennn/Dozer) (MIT)

## Contributing

Bug reports, ideas, and small PRs are very welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for a two-minute guide and a map of the
codebase.

## Support

Pelmet is free and open source. If it helps keep your menu bar tidy, you can
support maintenance, macOS compatibility work, and new features with a
[one-time or monthly contribution through Polar](https://buy.polar.sh/polar_cl_dmIB7LsoFtTdEnqBk5PBbK5OgB2v5Nw4Udw5d13Pi99).

## License

[MIT](LICENSE) © 2026 Ismat Babirli
