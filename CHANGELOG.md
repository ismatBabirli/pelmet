# Changelog

All notable changes to Pelmet are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet._

## [0.1.0] - 2026-07-13

First public release — the working MVP.

### Added

- **Hide / show managed icons** via an expanding-spacer trick (the same
  permission-free technique as Hidden Bar and Dozer), driven by a `‹ / ›`
  toggle or the global hotkey **⌥⌘B**.
- **The `╱` divider** — ⌘-drag icons to its right to keep them always visible;
  everything to its left is managed by Pelmet.
- **Notch-overflow detection** — a `+N` count appears on the toggle when
  expanded icons still don't fit beside the camera housing, using only public
  window-geometry metadata (no Screen Recording, no Accessibility).
- **The Shelf** — a blurred, rounded panel below the notch that lists the icons
  macOS hid, opened by clicking the count or pressing **⌥⌘N**. Renders each
  item's app icon and name — never a screen capture.
- **Opt-in Accessibility tier** — one-click activation of hidden items (and
  identification on macOS 26 Tahoe). Off by default; everything else works
  without it.
- Auto-rehide after a configurable delay, launch-at-login via `SMAppService`,
  a SwiftUI settings window, first-launch onboarding popovers, and a
  "Make Room…" remedies window (including tighter icon spacing).

### Notes

- Requires **macOS 13 Ventura** or later.
- The core hide/show experience needs **zero special permissions**.

[Unreleased]: https://github.com/ismatBabirli/pelmet/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ismatBabirli/pelmet/releases/tag/v0.1.0
