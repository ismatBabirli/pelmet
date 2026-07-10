# Contributing to Pelmet

Thanks for stopping by! Pelmet is a solo-maintained project, so the process is
deliberately lightweight — no forms, no committees.

## The short version

- **Found a bug or have an idea?** [Open an issue](https://github.com/ismatBabirli/pelmet/issues).
- **Small fix** (typo, small bug, doc tweak)? Send a PR directly.
- **Bigger change** (new feature, refactor)? Open an issue first so we can talk
  it through — and skim [PROJECT.md](PROJECT.md), it may already be on the roadmap.

## Dev setup

You need macOS 13+ and Xcode 15+ (Swift 5.9).

```bash
git clone https://github.com/ismatBabirli/pelmet.git
cd pelmet
swift run
```

That's the whole fast loop — the toggle and divider appear in your menu bar
immediately. The only thing `swift run` can't do is launch-at-login (it needs
a real .app bundle). To test that:

```bash
brew install xcodegen
xcodegen generate
open Pelmet.xcodeproj   # then build & run with ⌘R
```

## Map of the code

Everything lives in `Sources/Pelmet/` — about 350 lines total.

| File | What it does |
|---|---|
| `main.swift` | AppKit lifecycle entry point |
| `AppDelegate.swift` | Boot: accessory policy, manager, hotkey |
| `MenuBarManager.swift` | Core hide/show logic — the expanding-spacer trick |
| `HotkeyManager.swift` | Carbon global hotkey (⌥⌘B), permission-free |
| `Preferences.swift` | UserDefaults keys shared between AppKit and SwiftUI |
| `Settings/SettingsView.swift` | SwiftUI settings form |
| `Settings/SettingsWindowController.swift` | Hosts the settings window from an accessory app |

Two ground rules:

1. **The zero-permission core is sacred.** The default experience must never
   require Screen Recording or Accessibility. Features that need a permission
   (like the planned notch panel) are opt-in only.
2. **No dependencies so far.** Think twice before adding one.

## Code style

No linter is configured — just match the surrounding style:

- 4-space indentation, `// MARK: -` section headers
- `///` doc comments on types; inline comments explain *why*, especially around
  AppKit/Carbon quirks
- SwiftUI for windows, AppKit for the menu bar machinery

## Testing

There's no test suite yet — most of the code is AppKit plumbing that's hard to
unit test. CI checks that every PR compiles. Before sending a PR, please run
the manual smoke test:

1. `swift run`
2. Toggle with a click on ‹ / › and with ⌥⌘B
3. Open Settings (right-click the toggle), flip the options, relaunch, and
   confirm they persisted

If your change adds genuinely testable logic, a small XCTest target is very
welcome.
