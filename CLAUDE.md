<!-- Keep this file lean: pointers, not prose. The backticked doc paths below are
     deliberately NOT `@path` imports — imports load eagerly at launch and defeat
     the read-on-demand design. Read the referenced doc when the task touches its area. -->

# Pelmet

Open-source macOS menu-bar manager (menu-bar-only app, macOS 13+). AppKit app plus
SwiftUI settings windows. Sandbox is intentionally OFF, hardened runtime ON, and
`Sources/Pelmet/Pelmet.entitlements` is intentionally an empty dict.

## Commands

- Dev loop: `swift run` (SPM — fast, but not a real .app bundle). Tests: `swift test`.
- Real .app bundle (required for Sparkle, launch-at-login, and Accessibility/TCC
  testing): `xcodegen generate`, then
  `xcodebuild build -project Pelmet.xcodeproj -scheme Pelmet -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- Format before PRs: `swiftformat .` (conservative allowlist in `.swiftformat`; not CI-enforced).
- Release = push a `vX.Y.Z` tag — read `docs/RELEASING.md` first (runbook, secrets, dry-run).

## Architecture in 30 seconds

- `Sources/PelmetCore` — pure, unit-testable geometry/classification, no UI imports.
  Put genuinely testable logic here.
- `Sources/Pelmet` — the AppKit app: singleton managers (`MenuBarManager.shared`, …),
  SwiftUI settings panes, entry point `main.swift`.
- Full code map: `CONTRIBUTING.md` § "Map of the code". Collapse mechanism and
  hotkeys (⌥⌘B / ⌥⌘N): `README.md` § "How it works" and § "Usage".

## Testing

- Swift Testing (`@Test` / `#expect`), NOT XCTest. Unit tests cover `PelmetCore` only
  (`Tests/PelmetCoreTests`); the AppKit layer is manual-QA only — don't scaffold UI tests.
- On Command Line Tools-only machines `swift test` needs extra framework flags:
  `CONTRIBUTING.md` § "Testing".
- Manual QA matrix and debug env vars (`PELMET_DEBUG_ACTIVATION`, `PELMET_DEBUG_LAYOUT`,
  `PELMET_DISABLE_ACTIVATION`): `docs/shelf-verification.md`.

## Gotchas — deliberate, do not "fix"

- Swift 6 toolchain but Swift 5 **language mode** (`swiftLanguageModes: [.v5]` in
  `Package.swift`). Never migrate to the v6 language mode.
- `Pelmet.xcodeproj` and `Sources/Pelmet/Info.plist` are generated from `project.yml`
  and gitignored — never hand-edit them. Version numbers come from the git tag at
  release time — never hand-bump them.
- macOS TCC keys Accessibility grants to the code signature: test the opt-in
  Activation features from a bundled .app, never via `swift run`.
- Sparkle exists only in the XcodeGen build, behind `#if canImport(Sparkle)` — the
  plain SPM build must keep working without it.

## Product invariants (hard rules)

- The zero-permission core is sacred: the default experience must never require
  Screen Recording or Accessibility; permissioned features are strictly opt-in.
- No analytics, no accounts, no network calls — Sparkle update checks are the sole
  exception. No new dependencies (Sparkle is the only one).
- Rationale and full list: `PROJECT.md` § "5. Non-Goals" and § "6. Technical Foundation".

## Etiquette

- User-visible changes get a `CHANGELOG.md` entry under `[Unreleased]` (Keep a Changelog).
- PRs follow `.github/PULL_REQUEST_TEMPLATE.md`; run the manual smoke test in
  `CONTRIBUTING.md` § "Testing" first.
- CI (`.github/workflows/ci.yml`) runs `swift test` plus the xcodegen/xcodebuild
  bundle build; both must stay green.
- No AI attribution in commits or PRs — no `Co-Authored-By` trailers, no
  "Generated with" footers.
- Don't write em-dashes (`—`) in prose you add: code comments, docs,
  `CHANGELOG.md`, commit messages, and PRs. Use a colon, comma, parentheses, or
  a period instead. (Existing em-dashes stay; only what you add follows this.)
