# Changelog

All notable changes to Pelmet are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **About settings pane**: a new About pane shows Pelmet's version and build,
  a button to copy the version for bug reports, and links to the GitHub repo,
  release notes, and issue tracker, alongside the MIT license. The chevron's
  right-click menu also shows the current version. A plain `swift run` dev
  build (which has no bundle) reads "Development build".

## [0.2.0] - 2026-07-13

### Added

- **Sparkle auto-updates** — Pelmet now checks for new versions in-app via
  [Sparkle 2](https://sparkle-project.org). A "Check for Updates…" item sits in
  the chevron's right-click menu and the General settings pane gains a "Software
  Update" section. Updates are EdDSA-signed and delivered over an appcast served
  from GitHub Pages; the download stays a notarized `.zip` on GitHub Releases. On
  first launch Sparkle asks once whether to check automatically — nothing hits
  the network until you opt in.

### Changed

- The Settings window is reorganized into a System Settings-style sidebar
  with **General**, **Menu Bar Space**, and **One-Click Access** panes — a
  much shorter window with the same options — and it now remembers the
  last-selected pane.

### Fixed

- Onboarding tips could appear detached from the menu bar (floating
  mid-screen, seen on macOS 26). Tips now validate their anchor before
  showing, self-correct their position, close cleanly when Pelmet rebuilds
  its status items, and no longer burn their once-only flag when showing
  fails.

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

[Unreleased]: https://github.com/ismatBabirli/pelmet/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ismatBabirli/pelmet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ismatBabirli/pelmet/releases/tag/v0.1.0
