# Contributing to Pelmet

Thanks for stopping by! Pelmet is a solo-maintained project, so the process is
deliberately lightweight — no forms, no committees.

## The short version

- **Found a bug or have an idea?** [Open an issue](https://github.com/ismatBabirli/pelmet/issues).
- **Small fix** (typo, small bug, doc tweak)? Send a PR directly.
- **Bigger change** (new feature, refactor)? Open an issue first so we can talk
  it through — and skim [PROJECT.md](PROJECT.md), it may already be on the roadmap.

## Dev setup

You need a Swift 6 toolchain — Xcode 16+ or recent Command Line Tools (the
app itself runs on macOS 13+).

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

The app lives in `Sources/Pelmet/`; the pure, unit-tested notch/overflow
geometry lives in `Sources/PelmetCore/`.

| File | What it does |
|---|---|
| `main.swift` | AppKit lifecycle entry point |
| `AppDelegate.swift` | Boot: accessory policy, manager, hotkey |
| `MenuBarManager.swift` | Core hide/show logic — the expanding-spacer trick, toggle states, menu |
| `NotchLayoutMonitor.swift` | Event-driven measurement: when to look at the menu bar layout |
| `WindowListSource.swift` | The only window-server touchpoint (permission-free metadata) |
| `StatusItemRescuer.swift` | Safe recreate-at-position for Pelmet's own items |
| `HotkeyManager.swift` | Carbon global hotkey (⌥⌘B), permission-free |
| `Preferences.swift` | UserDefaults keys shared between AppKit and SwiftUI |
| `Settings/SettingsView.swift` | SwiftUI settings form |
| `Settings/SettingsWindowController.swift` | Hosts the settings window from an accessory app |
| `../PelmetCore/MenuBarLayoutClassifier.swift` | Pure geometry: which icons is macOS hiding at the notch |

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

The notch/overflow classifier in `PelmetCore` has a Swift Testing suite:

```bash
swift test
```

On a machine with only Command Line Tools (no Xcode), the Testing framework
isn't on the default search path — use:

```bash
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F$FW -Xlinker -F$FW \
  -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

The AppKit plumbing is still verified manually. Before sending a PR, please
run the smoke test:

1. `swift run`
2. Toggle with a click on ‹ / › and with ⌥⌘B
3. Open Settings (right-click the toggle), flip the options, relaunch, and
   confirm they persisted
4. On a notched MacBook with a crowded bar: confirm the +N count appears when
   expanded icons don't fit, and that right-click → Reset Divider Position
   brings the ╱ divider back next to the chevron

If your change adds genuinely testable logic, put it in `PelmetCore` with
tests alongside.
