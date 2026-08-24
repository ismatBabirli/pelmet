# Changelog

All notable changes to Pelmet are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.0] - 2026-08-24

### Added

- Detect permission-free top-center software-island candidates from local window
  geometry. Vibe Island works automatically through the built-in compatibility
  registry; unknown apps stay disabled until enabled and calibrated in Menu Bar
  Space settings. Thanks to [Yurii Rashkovskii](https://github.com/yrashk) for
  contributing this feature in [#43](https://github.com/ismatBabirli/pelmet/pull/43).
- Model a stable resting width for software-island detection so transient
  hover expansion does not make the covered-icon count jump. Calibration
  changes reclassify icons live while the Settings slider moves.

### Changed

- The hidden-icon count, Shelf, one-click access, and make-room guidance now work
  for both physical camera notches and enabled software islands.
- Software-island app identities and bundle identifiers remain local and are not
  added to anonymous telemetry.

### Fixed

- Enabling a software island no longer triggers Pelmet's physical-notch control
  rescue path, which could repack menu items and move a neighboring icon under
  the island.
- Covered-icon and update badges now render inside Pelmet's fixed-width toggle,
  so appearing or disappearing badge text cannot shift neighboring menu items.
- Software-island launch and quit events now update Settings even when the
  covered-icon count itself does not change, such as while Pelmet is collapsed.
- One-Click Access remains available in Settings while enabled after its island
  app quits, preserving the in-app path to turn the feature off.
- Software-island discovery now retains every detected display for an app and
  scans Window Server only once per layout measurement.

## [0.7.0] - 2026-08-10

### Added

- **Custom shortcuts.** Record your own combination for hide-and-show and for the
  Shelf in Settings → General → Shortcuts, or clear either one entirely. Still
  Carbon `RegisterEventHotKey`, so still no Accessibility permission. Pelmet checks
  a combination before accepting it and names what is in the way: macOS itself
  (including shortcuts you have remapped), Pelmet's other action, or another app
  that already claimed it. Shortcut labels follow your keyboard layout, so a Dvorak
  user sees the key they actually pressed. Existing installs keep ⌥⌘B and ⌥⌘N with
  nothing to do.

## [0.6.1] - 2026-08-05

### Changed

- One-click access now uses only pointer-free actions advertised through macOS
  Accessibility. Pelmet no longer creates synthetic mouse events, moves the
  cursor, or drags third-party menu bar items.

### Removed

- Profiles and default-profile application, because applying them required
  taking temporary control of the real pointer.

## [0.6.0] - 2026-08-05

### Added

- **Support Pelmet**: a Polar support link is available in the About pane and
  chevron menu, with a gentle in-app prompt after the GitHub star prompt. The
  prompt opens hosted Polar checkout, is rate-limited, and can be dismissed
  permanently.

## [0.5.0] - 2026-08-04

### Added

- **Profiles**: save identifiable menu bar arrangements, including divider
  membership and left-to-right order, then apply them from Settings or the
  chevron menu. Items that cannot be identified or are ambiguous remain
  unchanged and are reported. Applying a profile uses the existing opt-in
  Accessibility path; ordinary startup never prompts for permission.

## [0.4.2] - 2026-07-27

### Added

- A gentle prompt to star Pelmet on GitHub, shown a few days after first use
  once you have hidden icons at least once. It opens the repo in your browser,
  sends nothing, and can be dismissed for good.

## [0.4.1] - 2026-07-24

### Changed

- Automatic update checks now run every 6 hours after opt-in instead of daily.

## [0.4.0] - 2026-07-24

### Added

- **Show on hover** can now be enabled in General settings to reveal managed
  icons whenever the pointer enters the menu bar. It uses the existing
  permission-free divider and follows the configured auto-rehide behavior.

### Fixed

- The What's New window no longer clips its changelog link and Done button
  when resized to its minimum height.

## [0.3.3] - 2026-07-22

### Added

- Available updates now stay visible as a monochrome **↑** beside Pelmet's
  menu-bar toggle (combined as **+N ↑** when icons are hidden by the notch).
  Settings also shows the available version, retry state, and last successful
  check time.

### Changed

- Automatic update checks remain opt-in and run every 6 hours, while installing an
  update always requires approval in Sparkle's standard Install and Relaunch
  dialog. The release workflow now validates the app's update configuration,
  appcast XML, increasing build number, signed enclosure, downloadable ZIP,
  and publicly deployed feed item.

### Fixed

- A scheduled check that fails because the Mac is offline no longer disappears
  for a full day. Pelmet remembers the failure across relaunches, retries after
  connectivity returns or with bounded backoff, and stops after three recovery
  attempts so repeated failures cannot form a tight loop.

## [0.3.2] - 2026-07-21

### Added

- A native **What's New** window now appears once after each app update. It uses
  the changelog bundled with the app, includes every release skipped since the
  last acknowledged version, and links to the full changelog on GitHub. New
  installs start silently, while existing users see the feature's first release.

## [0.3.1] - 2026-07-21

### Fixed

- The anonymous usage notice now appears for existing users who upgrade while
  Pelmet is collapsed, so telemetry can start after the required disclosure
  instead of remaining inactive indefinitely. The notice also has a fallback
  when menu bar layout measurement does not produce a confirmed snapshot.

## [0.3.0] - 2026-07-19

### Added

- **Anonymous usage statistics (opt-out)**: Pelmet now sends one tiny anonymous
  event per day (app version, macOS version, chip type, and which Pelmet features
  are on) to a US-hosted PostHog instance, so we finally know how many installs
  exist and which features matter. Nothing is sent until an in-app notice has told
  you about it, and the first ping waits at least until the next launch or 24
  hours, whichever comes first. Turn it off any time in Settings, with
  `defaults write com.ismatbabirli.Pelmet telemetryEnabled -bool NO`, or by setting
  `DO_NOT_TRACK=1`. IP addresses are discarded, there are no names, no menu bar
  contents, and never anything about the other apps you run. Every field is
  documented in `docs/TELEMETRY.md`, alongside the one file of sending code.
- **Crash follow-up, local only**: if Pelmet quit unexpectedly, the next launch
  offers to open a prefilled GitHub issue with your Pelmet and macOS versions.
  Crash reports stay on your Mac; you review and attach them yourself. A "Report a
  Problem" button also lives in Settings > About.
- **About settings pane**: a new About pane shows Pelmet's version and build,
  a button to copy the version for bug reports, and links to the GitHub repo,
  release notes, and issue tracker, alongside the MIT license. The chevron's
  right-click menu also shows the current version. A plain `swift run` dev
  build (which has no bundle) reads "Development build".

### Fixed

- The crash follow-up no longer reveals an old, unrelated crash report. An
  unclean exit that leaves no fresh report (a Force Quit or `SIGKILL`) used to
  surface the newest Pelmet report of any age; it now only reveals a report from
  the last day.
- The "Report a Problem" prefill no longer sends a `labels` query parameter,
  which could make the prefilled GitHub issue fail to open for users without
  repo triage access. The label is still applied by the issue template.
- Overlapping daily heartbeat checks (for example a launch check and a wake
  check) can no longer send two pings for the same day.

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

[Unreleased]: https://github.com/ismatBabirli/pelmet/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/ismatBabirli/pelmet/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/ismatBabirli/pelmet/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/ismatBabirli/pelmet/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/ismatBabirli/pelmet/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ismatBabirli/pelmet/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/ismatBabirli/pelmet/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/ismatBabirli/pelmet/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/ismatBabirli/pelmet/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/ismatBabirli/pelmet/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/ismatBabirli/pelmet/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/ismatBabirli/pelmet/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ismatBabirli/pelmet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ismatBabirli/pelmet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ismatBabirli/pelmet/releases/tag/v0.1.0
