# Pelmet

An open-source macOS menu bar organizer. A pelmet is the board above a window that hides the curtain fittings — this one hides your menu bar clutter. Hide the icons you rarely need, reveal them with one click or a hotkey — so nothing disappears behind the MacBook notch anymore.

**Status: MVP scaffold** — hide/show works today with zero special permissions. The notch-aware floating panel is on the roadmap.

## The problem

On notched MacBooks, macOS silently hides menu bar items that don't fit next to the camera housing. There's no overflow indicator — the icons are just gone. Pelmet gives you back control.

## How it works (no private APIs, no permissions)

Pelmet places two items in your menu bar:

```
[hidden icons…]  ╱  [always-visible icons…]  ‹  clock
                 │                           │
             separator                    toggle
```

- **⌘-drag** any menu bar icon to the **left** of the ╱ separator.
- When collapsed, Pelmet inflates the separator's width to ~10,000 pt, pushing everything left of it past the screen edge. Expand and they slide back.
- This is the same battle-tested technique used by Hidden Bar and Dozer. It needs **no** Screen Recording or Accessibility permission.

## Usage

| Action | How |
|---|---|
| Show/hide managed icons | Click the ‹ / › toggle, or press **⌥⌘B** |
| Choose which icons are managed | ⌘-drag them left of the ╱ divider |
| Settings (auto-rehide, launch at login) | Right-click the toggle → Settings… |
| Quit | Right-click the toggle → Quit |

## Building & running

### Quick test (no Xcode project needed)

```bash
swift run
```

Runs as an accessory process — the toggle and divider appear in your menu bar immediately. Note: launch-at-login is unavailable in this mode (needs a real .app bundle).

### Proper .app bundle with XcodeGen

```bash
brew install xcodegen
xcodegen generate
open Pelmet.xcodeproj
```

Then build & run (⌘R). Archive → Distribute App → Direct Distribution for a notarized build.

### Manual Xcode project

1. Xcode → New Project → macOS App (name: Pelmet, interface: SwiftUI — we replace the lifecycle anyway).
2. Delete the generated `*App.swift` and `ContentView.swift`.
3. Drag everything from `Sources/Pelmet/` into the target.
4. In the target's Info tab, add **Application is agent (UIElement) = YES** (`LSUIElement`).

## Architecture

```
main.swift                    AppKit lifecycle entry point
AppDelegate.swift             Boot: accessory policy, manager, hotkey
MenuBarManager.swift          Core hide/show logic (expanding spacer)
HotkeyManager.swift           Carbon global hotkey (⌥⌘B), permission-free
Preferences.swift             UserDefaults keys shared with SwiftUI
Settings/SettingsView.swift   SwiftUI settings (auto-rehide, login item)
Settings/SettingsWindowController.swift
```

## Roadmap

- [ ] **Notch panel** — a blurred, rounded floating panel below the notch that renders hidden icons live via ScreenCaptureKit and forwards clicks with CGEvent. (Requires Screen Recording permission; keep it opt-in.)
- [ ] Show-on-hover: reveal when the mouse touches the menu bar
- [ ] Per-item rules and profiles (e.g. "presentation mode")
- [ ] Custom hotkey recorder (replace hardcoded ⌥⌘B)
- [ ] Sparkle auto-updates, Homebrew cask, notarized releases via GitHub Actions

## Prior art worth studying

- [Ice](https://github.com/jordanbaird/Ice) (MIT) — the most advanced open-source option; its "Ice Bar" panel is the reference for our notch panel
- [Hidden Bar](https://github.com/dwarvesf/hidden) (MIT) — origin of the expanding-spacer trick
- [Dozer](https://github.com/Mortennn/Dozer) (MIT)

## License

MIT
