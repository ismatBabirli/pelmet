# Manual verification — The Shelf & one-click access

The AppKit plumbing (panel, click matrix, activation) is verified by hand.
The pure logic (`ShelfContentDeriver`, `ShelfPlacement`, `StatusItemCorrelator`,
`AccessibilityActionSelector`, `QuiescencePolicy`, `ScreenCoordinates`) is
covered by the Swift Testing suite — run `swift test` (see CONTRIBUTING for the
Command-Line-Tools framework flags).

> **TCC needs a bundled build.** The Accessibility permission is keyed to the
> app's code signature/path. Grant/revoke testing (steps 8–11) must use the
> bundled `.app`, not `swift run` — grants under `swift run` are unreliable
> across rebuilds. Steps 1–7 work under `swift run`.

## Tier 0 — permission-free (no Accessibility grant)

On a notched Mac:

1. **Trigger the badge.** Add menu bar apps until the chevron shows `+N`.
   Confirm the count.
2. **Open on click.** Left-click the chevron → the Shelf fades in below the
   notch, frosted and rounded. The row count matches `N` (grouped rows sum to
   `N`).
3. **Identity tier.** On macOS ≤ 15 (Sequoia): rows show correct app icons and
   names — cross-check against which icons are visibly missing. On macOS 26
   (Tahoe): rows read "Hidden item 1…N" with the "macOS 26 hides which apps…"
   header (Control Center owns every window there).
4. **Tier-0 click.** Click a named row → its app comes forward and an inline
   callout explains one-click access is opt-in. (No engine yet, so no menu
   opens — that's expected.)
5. **Dismiss paths.** Reopen, then: press Esc → closes; reopen, click the
   desktop → closes; reopen, click the chevron again → closes.
6. **Space / display.** Reopen, switch Spaces (ctrl-→) → closes instantly.
   Reopen, unplug/replug an external display → closes, badge re-settles.
7. **Hotkey & empty state.** The Shelf shortcut (⌥⌘N by default) opens the Shelf,
   including over a fullscreen app. With nothing swallowed, it shows
   "Everything fits".
8. **Pref off.** Settings → turn off "Open the Shelf when clicking the count".
   Now a chevron click collapses/expands as before; the right-click menu's
   "See What's Hidden…" and the Shelf shortcut still open the Shelf.
9. **Toggle shortcut unchanged.** The toggle shortcut (⌥⌘B by default) always
   collapses/expands regardless of Shelf state.
10. **Auto-rehide paused.** Expand, open the Shelf, wait past the rehide delay
    → no collapse. Close the Shelf → collapse after a fresh full delay.

## Tier 1 — opt-in Accessibility (bundled build)

11. **Enable.** Settings → "Open hidden icons with one click" → the system
    Accessibility prompt appears once, Pelmet is listed under Privacy &
    Security → Accessibility. Grant it → "Accessibility permission: Granted"
    within ~2s of returning to Pelmet.
12. **Identity everywhere.** With `PELMET_DEBUG_ACTIVATION=verbose`, reopen the
    Shelf — rows now carry real app identity even on Tahoe (AX sweep).
13. **Pointer-safe activation.** Click a compatible row while watching the
    pointer → the item's menu or panel opens through `AXShowMenu` or `AXPress`,
    and the pointer stays over the Shelf row. Pelmet does not move any menu bar
    item.
14. **Unsupported item.** Click a row for an item that advertises neither
    supported Accessibility action → the Shelf explains that the item cannot
    be opened pointer-safely and suggests Make Room. The pointer and menu bar
    order stay unchanged.
15. **Revoke mid-use.** With the Shelf open, revoke Accessibility in System
    Settings → availability flips to "Not granted"; clicking a row reports the
    permission failure inline; the core hide/show is untouched.

## Safety rails

16. **Hung app.** `kill -STOP <pid>` a menu bar app, then open the Shelf → the
    AX sweep finishes within ~3s, no beachball (`kill -CONT` afterwards).
17. **Pointer invariant.** Exercise successful, unsupported, interrupted, and
    timed-out activation paths. In every case the pointer stays where the user
    left it and third-party menu bar item positions remain unchanged.
18. **Kill switch.** `PELMET_DISABLE_ACTIVATION=1 ./Pelmet` → clicks report the
    permission failure and no Accessibility action is performed.
19. **Upgrade cleanup.** Upgrade a profile containing saved Pelmet profiles
    from v0.5 or v0.6 → no Profiles pane or menu is shown, and relaunching does
    not rearrange menu bar items even if default-profile application was on.

## Accessibility

20. VoiceOver announces each row as a button with the app name; arrow keys
    move the selection; Return activates; Esc closes.
21. System Settings → Accessibility: Reduce Motion → the Shelf appears with no
    slide/fade. Reduce Transparency → the panel draws opaque.
22. `PELMET_DEBUG_LAYOUT=verbose swift run` → no repeating republish loop from
    PID-only churn (the digest ignores owner changes).

## Telemetry (anonymous daily ping)

23. **Dry run, nothing sent.** `PELMET_DEBUG_TELEMETRY=verbose swift run` → prints
    the gate decision and the exact JSON payload to stdout, and `active=false`
    (a `swift run` dev build is inert). Confirms the payload shape without a send.
    To actually send one from local for an end-to-end check, add
    `PELMET_FORCE_TELEMETRY=1` (developer hatch: unlocks the dev/debug/notice gates
    only, never beats `DO_NOT_TRACK`, `PELMET_DISABLE_TELEMETRY`, or an off
    preference). The day is recorded on success, so re-sending the same day needs
    `defaults delete com.ismatbabirli.Pelmet telemetryLastHeartbeatDay` first.
24. **Kill switch.** `PELMET_DISABLE_TELEMETRY=1` or `DO_NOT_TRACK=1` → the verbose
    trace shows `active=false`; the Settings toggle renders off and disabled under
    `DO_NOT_TRACK`.
25. **Inert Debug bundle.** In the XcodeGen Debug `.app`, telemetry stays off via
    `#if DEBUG` even though the bundle has a real version. Only a Release build with
    a real PostHog key (see `docs/TELEMETRY.md`) actually sends.
26. **First-run notice.** On a fresh user account the "Anonymous usage statistics" notice
    appears once, after the welcome tip, and does not stack on Sparkle's prompt.
    "Turn Off" flips the Settings toggle; nothing sends during that session.
27. **Crash follow-up (local only).** `kill -TRAP <pid>` a Release build, relaunch →
    the "Pelmet quit unexpectedly" alert offers a prefilled GitHub issue and reveals
    the newest `Pelmet-*.ips` in Finder. A normal quit or Ctrl-C does not trigger it.

## Shortcuts (custom recorder)

Carbon `RegisterEventHotKey` needs no permission, so steps 28 to 39 all work under
`swift run`. Steps 40 and 41 need the bundled `.app`: `swift run` has no bundle
identifier, so it writes a different defaults domain and persistence there proves
nothing.

28. **Defaults on a fresh domain.** `defaults delete com.ismatbabirli.Pelmet
    toggleShortcut shelfShortcut`, relaunch → Settings → General → Shortcuts shows
    ⌥⌘B and ⌥⌘N, both fire, and "Restore Default Shortcuts" is disabled.
29. **Record.** Click the "Hide and show icons" recorder, press ⌥⌘J → it commits,
    ⌥⌘J toggles, and the old ⌥⌘B no longer does anything.
30. **The old shortcut is recordable.** With ⌥⌘B still bound, begin recording and
    press ⌥⌘B: it must be *recorded*, not toggle the menu bar. This is the proof
    that Pelmet's own hotkeys stand down while the recorder is armed.
31. **Duplicate.** Record the Shelf's combination into "Hide and show icons" → red
    `⌥⌘N is already used by "Open the Shelf"`, the control stays armed, and Esc
    leaves it unchanged.
32. **Rejection sentences.** Try a bare `B` (asks for ⌘, ⌥ or ⌃), `⌘B` (asks for one
    more modifier), and `⌃←` (names Switching Spaces). Note that ⌘Space never
    reaches Pelmet at all, because Spotlight consumes it first: that is expected,
    and the reserved table is what turns it into a sentence when it does arrive.
33. **A remapped system shortcut is refused.** Change a shortcut in System Settings
    → Keyboard → Keyboard Shortcuts, then try to record it → refused as "macOS".
34. **Esc and clear.** Esc restores the previous glyph. ⌫ (or the ✕ button) clears →
    the control reads "Record Shortcut", the chevron tooltip loses its parenthesis,
    and the right-click menu item loses its accelerator.
35. **Positional keys need one modifier.** ⌘F5 and ⌥↑ are accepted, because no app
    loses a keystroke it needs.
36. **Swap both.** Set the two actions to each other's combinations in turn and
    confirm both still fire. This is the proof that registration unregisters
    everything before registering anything.
37. **Keyboard only.** With System Settings → Keyboard → Keyboard navigation on: Tab
    reaches the recorder, the focus ring is visible, and Space and Return both begin
    recording.
38. **VoiceOver.** The control announces "<row label> shortcut" and reads the value
    as "Option Command B", and re-announces after a change.
39. **Claimed by another app.** Bind a combination in another app first (Raycast,
    Alfred, System Settings → Keyboard Shortcuts), then set the same one in Pelmet →
    red "Another app is already using …", and the `swift run` banner reports it as
    unavailable. Note that registration *succeeding* is not proof a shortcut fires:
    an event-tap app (Raycast, Karabiner, Hammerspoon) can intercept ahead of
    Carbon, and there is no permission-free way to detect that.
40. **Persistence (bundled).** Relaunch → custom shortcuts survive, and the tooltip,
    the right-click accelerators and the replayed onboarding copy all quote them.
41. **Layout change (bundled).** Switch to Dvorak while running → the label follows
    the layout without a relaunch, and the same physical key still fires.
42. **Corrupt value.** `defaults write com.ismatbabirli.Pelmet toggleShortcut
    -string garbage`, relaunch → falls back to ⌥⌘B with one os_log line and no
    crash, and the bad value is left in place for diagnosis.
