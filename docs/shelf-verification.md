# Manual verification — The Shelf & one-click access

The AppKit plumbing (panel, click matrix, activation) is verified by hand.
The pure logic (`ShelfContentDeriver`, `ShelfPlacement`, `StatusItemCorrelator`,
`ActivationPlanner`, `DragPlanner`, `ActivationSession`, `ScreenCoordinates`)
is covered by the Swift Testing suite — run `swift test` (see CONTRIBUTING for
the Command-Line-Tools framework flags).

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
7. **Hotkey & empty state.** ⌥⌘N opens the Shelf, including over a fullscreen
   app. With nothing swallowed, ⌥⌘N shows "Everything fits".
8. **Pref off.** Settings → turn off "Open the Shelf when clicking the count".
   Now a chevron click collapses/expands as before; the right-click menu's
   "See What's Hidden…" and ⌥⌘N still open the Shelf.
9. **⌥⌘B unchanged.** ⌥⌘B always collapses/expands regardless of Shelf state.
10. **Auto-rehide paused.** Expand, open the Shelf, wait past the rehide delay
    → no collapse. Close the Shelf → collapse after a fresh full delay.

## Tier 1 — opt-in Accessibility (bundled build)

11. **Enable.** Settings → "Open hidden icons with one click" → the system
    Accessibility prompt appears once, Pelmet is listed under Privacy &
    Security → Accessibility. Grant it → "Accessibility permission: Granted"
    within ~2s of returning to Pelmet.
12. **Identity everywhere.** With `PELMET_DEBUG_ACTIVATION=verbose`, reopen the
    Shelf — rows now carry real app identity even on Tahoe (AX sweep).
13. **Visible-item click.** Click a row whose item is visible → its menu opens
    under the item, cursor returns to where it was.
14. **Swallowed-item click.** Click a row whose item is behind the notch →
    watch the strategy chain (speculative click → AXPress → drag-to-expose).
    The item's menu opens; after you close it, the moved neighbor returns to
    its slot (menu bar order preserved).
15. **Revoke mid-use.** With the Shelf open, revoke Accessibility in System
    Settings → availability flips to "Not granted"; clicking a row reports the
    permission failure inline; the core hide/show is untouched.

## Safety rails

16. **Hung app.** `kill -STOP <pid>` a menu bar app, then open the Shelf → the
    AX sweep finishes within ~3s, no beachball (`kill -CONT` afterwards).
17. **User race.** Start an activation, then immediately move the physical
    mouse / press a button → the session aborts cleanly, no stuck synthetic
    button (verify with a manual click afterwards).
18. **Kill switch.** `PELMET_DISABLE_ACTIVATION=1 ./Pelmet` → clicks report the
    permission failure and never post synthetic events.

## Accessibility

19. VoiceOver announces each row as a button with the app name; arrow keys
    move the selection; Return activates; Esc closes.
20. System Settings → Accessibility: Reduce Motion → the Shelf appears with no
    slide/fade. Reduce Transparency → the panel draws opaque.
21. `PELMET_DEBUG_LAYOUT=verbose swift run` → no repeating republish loop from
    PID-only churn (the digest ignores owner changes).

## Telemetry (anonymous daily ping)

22. **Dry run, nothing sent.** `PELMET_DEBUG_TELEMETRY=verbose swift run` → prints
    the gate decision and the exact JSON payload to stdout, and `active=false`
    (a `swift run` dev build is inert). Confirms the payload shape without a send.
23. **Kill switch.** `PELMET_DISABLE_TELEMETRY=1` or `DO_NOT_TRACK=1` → the verbose
    trace shows `active=false`; the Settings toggle renders off and disabled under
    `DO_NOT_TRACK`.
24. **Inert Debug bundle.** In the XcodeGen Debug `.app`, telemetry stays off via
    `#if DEBUG` even though the bundle has a real version. Only a Release build with
    a real PostHog key (see `docs/TELEMETRY.md`) actually sends.
25. **First-run notice.** On a fresh profile the "Anonymous usage statistics" notice
    appears once, after the welcome tip, and does not stack on Sparkle's prompt.
    "Turn Off" flips the Settings toggle; nothing sends during that session.
26. **Crash follow-up (local only).** `kill -TRAP <pid>` a Release build, relaunch →
    the "Pelmet quit unexpectedly" alert offers a prefilled GitHub issue and reveals
    the newest `Pelmet-*.ips` in Finder. A normal quit or Ctrl-C does not trigger it.
