# Pelmet — Project Vision & Roadmap

> A pelmet is the board above a window that hides the curtain fittings.
> This one hides your menu bar clutter.

**Pelmet** is a free, open-source (MIT) menu bar organizer for macOS. It gives users back control of the icons that vanish behind the MacBook notch — with beautiful visuals, zero required permissions to start, and full transparency about what the app does.

---

## 1. The Problem

On notched MacBooks (Air and Pro, 2021 onward), the menu bar loses a large slice of usable space to the camera housing. macOS handles the overflow in the worst possible way: **items that don't fit are silently hidden.** There is no overflow indicator, no "more…" chevron, no way to reach them. Users with many status icons — VPNs, password managers, sync clients, audio tools — simply lose access to some of them and often don't realize it.

Existing solutions have gaps:

| Solution | Gap |
|---|---|
| **Bartender** ($20, closed source) | Was silently acquired in 2024, causing a community trust crisis over its Screen Recording + Accessibility permissions |
| **Hidden Bar / Dozer** (open source) | Reliable but minimal — no notch panel, dated visuals, sparse maintenance |
| **Ice** (open source) | Excellent and feature-rich, but complex; requires macOS 14+ and heavy permissions for its advanced features |

## 2. Our Idea

Pelmet occupies a deliberate position in that landscape:

1. **Trust first.** The core hide/show feature works with **zero special permissions** — no Screen Recording, no Accessibility. Every feature that needs a permission is opt-in, clearly explained, and degradable: decline the permission and the app still works.
2. **Beauty as a feature.** Fluid animations, a gorgeous frosted panel under the notch, thoughtful micro-interactions. Open-source utilities don't have to look utilitarian.
3. **Actionable, not just tidy.** Hidden icons shouldn't just be stored — they should be one hover, hotkey, or search away.
4. **Simple by default, powerful by choice.** A first-time user needs to understand the app in 30 seconds. Power features (profiles, triggers, rules) live one layer deeper.

## 3. Core Concepts

```
[hidden icons…]  ╱  [always-visible icons…]  ‹  clock
                 │                           │
             separator                    toggle
```

- **The divider (╱):** everything the user ⌘-drags to its left is managed by Pelmet.
- **Collapse mechanism:** the divider inflates to ~10,000 pt, pushing managed items past the screen edge. Battle-tested (Hidden Bar, Dozer), permission-free.
- **The Shelf (phase 2):** a floating, blurred panel below the notch that shows hidden icons live and forwards clicks — so items are usable *without* rearranging the menu bar.

## 4. Feature Plan by Phase

### ✅ Phase 0 — MVP (done: scaffold)

*Goal: a working, trustworthy hide/show tool anyone can build and run.*

- Hide/show via expanding divider, toggle button, and global hotkey (⌥⌘B)
- Auto-rehide after a configurable delay
- SwiftUI settings window; launch at login (SMAppService)
- Runs via `swift run`, XcodeGen, or manual Xcode project
- Zero permissions required

### 🔨 Phase 1 — Polish & Distribution

*Goal: something people can install and love in under a minute.*

- **Fluid animations** for expand/collapse (the "Vanilla moment" — icons glide, not blink)
- **Show on hover / scroll:** reveal hidden items when the pointer touches the menu bar or the user scrolls on it
- **Custom hotkey recorder** (replace hardcoded ⌥⌘B)
- **Onboarding:** first-launch walkthrough teaching the ⌘-drag gesture
- **App icon & identity:** pelmet/curtain metaphor, warm and crafted
- **Distribution pipeline:** GitHub Actions → build, codesign, notarize → GitHub Releases + Homebrew cask (`brew install --cask pelmet`) + Sparkle auto-updates
- Multi-display awareness and menu bar changes across Spaces

### 🌟 Phase 2 — The Shelf (flagship feature)

*Goal: the beautiful, actionable answer to the notch.*

A **floating frosted panel** below the notch listing exactly the icons macOS
hid, opened by clicking the "+N" count (or ⌥⌘N). Two tiers, degrading
gracefully:

- **Tier 0 — permission-free.** Rows render as the owning app's icon + name
  (via `NSRunningApplication`), never captured pixels. On macOS ≤ 15 owners
  come free from `CGWindowListCopyWindowInfo`; on macOS 26 Tahoe — where
  Control Center re-parents every status-item window — rows honestly show as
  "Hidden item N" until the user opts into Tier 1. Clicking a row brings the
  owning app forward and offers the opt-in.
- **Tier 1 — opt-in Accessibility.** One toggle enables reading which app
  owns each item (restoring identity on Tahoe) and **single-click activation**
  of the real item via synthetic events, with a make-room/drag-to-expose
  fallback for items in the notch dead zone. Plain-language consent; never
  reads the screen; fully degradable — turn it off and Tier 0 keeps working.

> **Why not ScreenCaptureKit?** The original spec captured live item pixels.
> Verified dead end (mid-2026): Screen Recording brings recurring
> re-approval prompts and a permanent purple indicator, the capture APIs are
> obsoleted (the maintained Ice fork resorts to a private, leaking SkyLight
> call), and it contradicts Pelmet's permission-free positioning. An
> **Accessibility-first** design (proven by MenuDown, ChocolateBar) is the
> trust-preserving answer.

- Interaction: always-visible "+N" indicator → click-to-open (hover is a
  later opt-in accelerator, never the only path); single-click activation;
  never auto-reorders the main bar; real buttons for VoiceOver + keyboard nav.
- Appearance: `NSVisualEffectView` blur, rounded corners, respects Reduce
  Transparency / Reduce Motion. Enabled on the notched built-in display.

> **macOS 27 "Golden Gate" (ships ~Sept 2026)** adds a native overflow button
> and merges all status items into a single window, breaking the expanding-
> spacer mechanic and per-item detection every manager relies on. Pelmet's
> engine already degrades to a frames-only honest state via a runtime
> re-parenting heuristic (the same tripwire that handles Tahoe); a dedicated
> macOS 27 compatibility pass is its own follow-up. The Shelf's audience
> until then is the large Sequoia/Tahoe installed base, which gets nothing
> native.

### ⚡ Phase 3 — Actionable Power Features

*Goal: from tidy to fast.*

- **Quick Search (⌘ space-style):** type to find and activate any menu bar item, hidden or not
- **Profiles:** named icon arrangements — "Work", "Presentation", "Travel" — switchable manually or by hotkey
- **Triggers:** auto-switch profiles based on Focus mode, connected display, battery state, or active app
- **Per-item rules:** always show, always hide, show only when updating
- **Presentation mode:** one action hides everything sensitive before screen sharing

### 🧭 Phase 4 — Community & Ecosystem

*Goal: a project that outlives its first author.*

- Localization (community-driven)
- Full accessibility pass (VoiceOver, Reduce Motion, keyboard-only use)
- Scripting hooks: URL scheme + Shortcuts actions (`pelmet://toggle`, `pelmet://profile/work`)
- Contributor docs, good-first-issue backlog, architecture guide
- Public roadmap voting via GitHub Discussions

## 5. Non-Goals

- **No menu bar "styling"** (tints, borders) in early phases — Ice does this well; we stay focused
- **No Screen Recording, ever** — the Shelf renders app icons/names, not captured pixels; the purple indicator and re-approval nags are exactly what users flee
- **No Mac App Store initially** — the sandbox is incompatible with the Shelf; direct + Homebrew distribution instead
- **No analytics, no accounts, no network calls** except Sparkle update checks

## 6. Technical Foundation

| Area | Choice |
|---|---|
| Language / UI | Swift 6 toolchain (Swift 5 language mode), SwiftUI for windows, AppKit for menu bar machinery |
| Minimum macOS | 13 Ventura (all phases) |
| Hide mechanism | `NSStatusItem` expanding spacer (no private APIs) |
| Shelf rendering | App icon + name from `NSRunningApplication` (no screen capture) |
| Item identity | `CGWindowListCopyWindowInfo` owner PID (≤ Sequoia); `kAXExtrasMenuBarAttribute` sweep (Tahoe, opt-in Accessibility) |
| Click forwarding | Synthetic `CGEvent` at real item coordinates + drag-to-expose fallback (opt-in Accessibility) |
| Hotkeys | Carbon `RegisterEventHotKey` (permission-free) |
| Updates | Sparkle 2 |
| CI/CD | GitHub Actions: build → sign → notarize → release |
| License | MIT |

## 7. Success Criteria

- A newcomer goes from `brew install` to organized menu bar in **< 2 minutes** without reading docs
- Phase 0–1 features run with **zero permission prompts**
- The Shelf is praised for looking *native-plus* — like something Apple could have shipped
- External contributors merge meaningful PRs by end of Phase 3

## 8. Going Public — Launch-Day Checklist

The repo is private while the MVP matures. Dependabot, Actions least-privilege
(GitHub-owned/verified actions only, read-only token), and merge hygiene are
already configured — but GitHub gates the protections below on private
free-plan repos ("Upgrade to GitHub Pro or make this repository public").
Run these the day the repo goes public, then delete this section.

- [ ] Make the repository public (Settings → General → Danger Zone)
- [ ] Re-enable CI: rename `.github/workflows/ci.yml.disabled` back to `ci.yml`,
      uncomment it, and restore the CI badge in `README.md` (steps are in the
      file's header; Actions minutes are free on public repos)
- [ ] Branch protection for `main` — requires PRs (no approval count, solo-friendly),
      blocks force-pushes and deletion; admins can bypass so you're never locked out:

  ```bash
  gh api -X POST repos/ismatBabirli/pelmet/rulesets --input - <<'JSON'
  {
    "name": "protect-main",
    "target": "branch",
    "enforcement": "active",
    "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
    "rules": [
      {"type": "deletion"},
      {"type": "non_fast_forward"},
      {"type": "pull_request", "parameters": {"required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true, "require_code_owner_review": false,
        "require_last_push_approval": false, "required_review_thread_resolution": false}}
    ],
    "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]
  }
  JSON
  ```

- [ ] Secret scanning push protection (alert scanning turns on automatically for public repos):

  ```bash
  echo '{"security_and_analysis":{"secret_scanning_push_protection":{"status":"enabled"}}}' \
    | gh api -X PATCH repos/ismatBabirli/pelmet --input -
  ```

- [ ] Private vulnerability reporting (SECURITY.md links to it):

  ```bash
  gh api -X PUT repos/ismatBabirli/pelmet/private-vulnerability-reporting
  ```

- [ ] Require approval before outside contributors' workflows run:

  ```bash
  echo '{"approval_policy":"all_external_contributors"}' \
    | gh api -X PUT repos/ismatBabirli/pelmet/actions/permissions/fork-pr-contributor-approval --input -
  ```

- [ ] Record a short demo GIF and replace the `TODO(screenshot)` placeholder in the README hero
