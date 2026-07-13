import AppKit
import PelmetCore

/// Manages two NSStatusItems:
///
///  ┌────────────────────────── menu bar ──────────────────────────┐
///  │  [hidden icons...]  |separator|  [always-visible icons...] [toggle]  clock │
///  └───────────────────────────────────────────────────────────────┘
///
/// Anything to the LEFT of the separator is controlled by Pelmet. When
/// collapsed, the separator's length is inflated to push everything left of
/// it off the screen edge — the same technique used by Hidden Bar / Dozer.
/// No private APIs, no Screen Recording or Accessibility permission required.
///
/// On notched MacBooks, macOS silently refuses to draw status items that
/// don't fit beside the notch. Pelmet can't force them on screen (nobody
/// can, without heavy permissions) — but it detects the situation via
/// NotchLayoutMonitor and says so on the toggle, so an expand that can't
/// show everything doesn't just look broken.
final class MenuBarManager: NSObject {

    static let shared = MenuBarManager()

    // MARK: - Configuration

    private let expandedSeparatorLength: CGFloat = 10

    /// Collapse works by inflating the separator so items left of it are
    /// pushed past the screen edge. Bounded because huge lengths misbehave:
    /// macOS 26.5 silently caps a status item window near 5,000pt (measured
    /// — a 10,000pt request displaces neighbors by only ~5,000), and Hidden
    /// Bar saw pathological layout behavior with unbounded values.
    private var collapsedSeparatorLength: CGFloat {
        let widestScreen = NSScreen.screens.map(\.frame.width).max() ?? 2_000
        return max(500, min(widestScreen + 200, 4_000))
    }

    private let toggleAutosaveName = "Pelmet_Toggle"
    private let separatorAutosaveName = "Pelmet_Separator"

    // MARK: - State

    private(set) var isCollapsed = false
    private var rehideTimer: Timer?

    private var toggleItem: NSStatusItem!
    private var separatorItem: NSStatusItem!

    /// Latest confirmed layout facts from NotchLayoutMonitor.
    private var swallowedCount = 0
    private var separatorSwallowed = false
    private var latestClassification: LayoutClassification?

    private var toggleRescueAttempts = 0
    private var lastToggleRescue = Date.distantPast

    /// One-shot fallback so first-run onboarding isn't hostage to a confirmed
    /// layout that a busy bar may never produce.
    private var firstRunWelcomeTimer: Timer?

    /// The Shelf's seam to the opt-in activation machinery. Always present;
    /// degrades honestly when the Accessibility grant is absent.
    var shelfEngine: StatusItemActivating { StatusItemActivationEngine.shared }

    // MARK: - Setup

    func setUp() {
        seedFirstLaunchPositionsIfNeeded()

        // variableLength so the "+N" overflow count fits next to the chevron;
        // with an empty title the width matches the old square item.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = toggleAutosaveName
        toggleItem.behavior = []
        // Assigning autosaveName adopts persisted state, so un-hide AFTER it —
        // recovers an item ⌘-dragged out of the bar by an earlier build.
        toggleItem.isVisible = true
        configureToggleButton(toggleItem)

        separatorItem = NSStatusBar.system.statusItem(withLength: expandedSeparatorLength)
        separatorItem.autosaveName = separatorAutosaveName
        separatorItem.isVisible = true
        configureSeparatorButton(separatorItem)

        NotchLayoutMonitor.shared.attach(
            separator: separatorItem,
            toggle: toggleItem,
            isCollapsed: { [weak self] in self?.isCollapsed ?? false }
        )
        NotchLayoutMonitor.shared.onConfirmedChange = { [weak self] classification in
            self?.apply(classification)
        }

        // Recompute the bounded collapse length when displays change.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isCollapsed else { return }
            self.separatorItem.length = self.collapsedSeparatorLength
        }

        // Never auto-collapse under an open tip popover or Pelmet window;
        // restart the full delay once everything is closed.
        UIActivityTracker.shared.onFirstOpened = { [weak self] in
            self?.rehideTimer?.invalidate()
        }
        UIActivityTracker.shared.onAllClosed = { [weak self] in
            guard let self, !self.isCollapsed else { return }
            self.scheduleRehideIfNeeded()
        }

        // The Settings toggle for the chevron count writes straight to
        // UserDefaults (@AppStorage); reflect changes immediately.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateToggleIcon()
        }

        // Restore the last collapse state. First launch starts EXPANDED and
        // STAYS expanded — nothing hides until the user acts. Auto-rehide
        // follows a user-initiated reveal, NOT this launch restore.
        if Preferences.isCollapsed {
            collapse()
        } else {
            expand(scheduleRehide: false)
        }

        StatusItemActivationEngine.shared.start()
        // The engine's directory changes on its own schedule (grant lands,
        // AX sweep enriches identity) — independent of the layout digest, so
        // re-derive Shelf rows when it does.
        shelfEngine.onDirectoryChange = { [weak self] _ in
            self?.refreshShelfEntries()
        }

        NotchLayoutMonitor.shared.requestMeasurement(reason: .launch)
        armFirstRunWelcomeFallback()
    }

    /// If the layout never settles into a confirmed classification, `apply()`
    /// never fires and onboarding would never run. After a short delay, drive
    /// the checks directly — `maybeShowLaunchTips`/`maybeOfferOneClick` are
    /// layout-independent and the `didShowToggleTip`/`didOfferOneClick` gates
    /// keep this idempotent with the confirmed path.
    private func armFirstRunWelcomeFallback() {
        guard !Preferences.didShowToggleTip else { return }
        firstRunWelcomeTimer = Timer.scheduledTimer(
            withTimeInterval: 4, repeats: false
        ) { [weak self] _ in
            self?.reapplyOnboardingChecks()
        }
    }

    /// macOS stores each status item's position in UserDefaults under
    /// "NSStatusItem Preferred Position <autosaveName>" — an order hint where
    /// smaller = closer to the RIGHT screen edge. Undocumented but stable;
    /// Hidden Bar and Ice rely on it, and Ice seeds exactly these values.
    ///
    /// Without a seed, a brand-new item is inserted at the LEFT end of the
    /// item area — on notched MacBooks exactly the region macOS silently
    /// swallows when the bar is full, which made the ╱ divider invisible on
    /// crowded bars (and a first launch look completely dead). Seeding the
    /// toggle at 0 and the divider at 1 places both next to the clock, where
    /// they are always visible. The divider starts with every icon on its
    /// managed (left) side: nothing hides until the user collapses, and the
    /// icons to keep visible are ⌘-dragged to the RIGHT of ╱.
    ///
    /// Per-key guards make this self-healing: an existing install whose
    /// divider was never ⌘-dragged (because it was born invisible) has no
    /// separator key, so the seed applies on the next launch.
    private func seedFirstLaunchPositionsIfNeeded() {
        let seeds: [(name: String, position: CGFloat)] = [
            (toggleAutosaveName, 0),
            (separatorAutosaveName, 1),
        ]
        for seed in seeds {
            let key = "NSStatusItem Preferred Position \(seed.name)"
            if UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(seed.position, forKey: key)
            }
        }
    }

    private func configureToggleButton(_ item: NSStatusItem) {
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(toggleButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel("Pelmet")
    }

    private func configureSeparatorButton(_ item: NSStatusItem) {
        guard let button = item.button else { return }
        button.image = separatorImage()
        button.appearsDisabled = true
        button.toolTip = "Pelmet hides everything left of this divider. ⌘-drag icons you always want visible to its right."
        button.setAccessibilityLabel("Pelmet divider")
    }

    // MARK: - Public actions

    func toggle() {
        isCollapsed ? expand() : collapse()
    }

    func expand(scheduleRehide: Bool = true) {
        isCollapsed = false
        Preferences.isCollapsed = false
        separatorItem.length = expandedSeparatorLength
        separatorItem.button?.image = separatorImage()
        updateToggleIcon()
        if scheduleRehide { scheduleRehideIfNeeded() }
        NotchLayoutMonitor.shared.requestMeasurement(reason: .expandSettled)
    }

    func collapse() {
        // A Shelf left open over a collapsing bar would show stale rows.
        ShelfPanelController.shared.hide(animated: false)
        isCollapsed = true
        Preferences.isCollapsed = true
        rehideTimer?.invalidate()
        separatorItem.length = collapsedSeparatorLength
        // Hide the divider glyph while it's a giant invisible spacer.
        separatorItem.button?.image = nil
        // A count would now include the icons we intentionally hid — clear
        // immediately rather than waiting for the next measurement.
        swallowedCount = 0
        separatorSwallowed = false
        updateToggleIcon()
        NotchLayoutMonitor.shared.requestMeasurement(reason: .collapseSettled)
    }

    // MARK: - Layout monitoring

    private func apply(_ classification: LayoutClassification) {
        latestClassification = classification
        swallowedCount = classification.swallowedCount
        separatorSwallowed = !isCollapsed && classification.separatorHealth == .swallowed
        updateToggleIcon()

        refreshShelfEntries()

        if isCollapsed, classification.offscreenLeftCount > 0, !Preferences.hasEverManagedItems {
            Preferences.hasEverManagedItems = true
        }

        if !classification.toggleVisible {
            rescueToggleIfNeeded()
        }

        reapplyOnboardingChecks()
    }

    /// Re-derives Shelf rows from the latest confirmed layout and the
    /// engine's current directory, then pushes them to SwiftUI and any open
    /// panel. Called both on a new layout snapshot AND when the engine's
    /// directory changes (e.g. the Accessibility grant lands and the AX
    /// sweep enriches identity) — the layout digest doesn't move on a grant,
    /// so without this second trigger an open Shelf would stay stale.
    func refreshShelfEntries() {
        // Prefer the monitor's confirmed snapshot: on a fresh layout the
        // engine's directory-change fires (via the multicast) before apply()
        // updates our own `latestClassification`, so reading the monitor
        // avoids deriving against a one-snapshot-stale classification.
        guard let classification = NotchLayoutMonitor.shared.confirmed ?? latestClassification else { return }
        let pids = Set(classification.items.flatMap(\.ownerPIDs))
        let entries = ShelfContentDeriver.derive(
            classification: classification,
            apps: OwnerResolver.shared.resolve(pids: pids),
            controlCenterPID: OwnerResolver.shared.controlCenterPID(),
            ownPID: Int32(ProcessInfo.processInfo.processIdentifier),
            engineItems: shelfEngine.activatableDescriptors
        )
        LayoutStatus.shared.refresh(swallowedCount: classification.swallowedCount, shelfEntries: entries)
        ShelfPanelController.shared.update(entries: entries)
    }

    /// Runs the pending one-time tips against the latest confirmed layout.
    /// Called on every confirmed snapshot and again when a tip closes (the
    /// tips chain: divider → toggle → count education).
    func reapplyOnboardingChecks() {
        guard !isCollapsed else { return }
        // The welcome and the one-click offer are layout-independent, so they
        // still run before any classification confirms (a busy just-logged-in
        // bar may never settle). Swallowed-education needs a real count.
        let classification = latestClassification
        OnboardingController.shared.maybeShowLaunchTips(
            separator: separatorItem,
            toggle: toggleItem,
            separatorVisible: classification?.separatorHealth == .visible,
            toggleVisible: classification?.toggleVisible ?? true
        )
        if let classification {
            OnboardingController.shared.maybeShowSwallowedEducation(
                count: classification.swallowedCount,
                toggle: toggleItem
            )
            OnboardingController.shared.maybeShowShelfTip(
                count: classification.swallowedCount,
                toggle: toggleItem
            )
        }
        OnboardingController.shared.maybeOfferOneClick(toggle: toggleItem)
    }

    /// The toggle is the escape hatch — if it ever gets swallowed the user
    /// has no way back, so it alone is rescued automatically (rate-limited).
    private func rescueToggleIfNeeded() {
        guard toggleRescueAttempts < 2,
              Date().timeIntervalSince(lastToggleRescue) > 60 else { return }
        toggleRescueAttempts += 1
        lastToggleRescue = Date()

        if isCollapsed {
            // Collapsed with an unreachable toggle means locked out: reveal
            // first so the rescued toggle has somewhere visible to land.
            expand(scheduleRehide: false)
        }
        toggleItem = StatusItemRescuer.recreate(
            toggleItem,
            autosaveName: toggleAutosaveName,
            length: NSStatusItem.variableLength,
            preferredPosition: 0,
            configure: { [weak self] item in self?.configureToggleButton(item) }
        )
        updateToggleIcon()
        NotchLayoutMonitor.shared.reattach(separator: separatorItem, toggle: toggleItem)
    }

    // MARK: - UI plumbing

    /// Left-click matrix. The behavior differs from plain toggle ONLY when
    /// the "+N" badge is visibly present — the button looks different in
    /// exactly the states where it acts differently:
    ///
    ///   shelf open                              → close the Shelf
    ///   collapsed                               → expand (unchanged)
    ///   expanded, nothing swallowed             → collapse (unchanged)
    ///   expanded, +N showing, shelf enabled     → open the Shelf
    ///   expanded, +N showing, shelf disabled    → collapse (pre-Shelf behavior)
    ///
    /// ⌥⌘B always means plain toggle; right-click always means the menu.
    @objc private func toggleButtonClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if ShelfPanelController.shared.isVisible {
            ShelfPanelController.shared.hide()
            return
        }
        // Only diverge to "open Shelf" when the "+N" badge is actually
        // visible — same condition updateToggleIcon() draws it under. If the
        // user hid the count, the chevron looks like the plain toggle and
        // must act like it.
        if !isCollapsed, swallowedCount > 0,
           Preferences.showSwallowedCount, Preferences.shelfEnabled {
            openShelf(reason: .toggleClick)
            return
        }
        toggle()
    }

    // MARK: - Shelf

    func openShelfFromHotkey() {
        if ShelfPanelController.shared.isVisible {
            ShelfPanelController.shared.hide()
        } else {
            openShelf(reason: .hotkey)
        }
    }

    @objc private func openShelfFromMenu() {
        openShelf(reason: .menu)
    }

    private func openShelf(reason: ShelfPanelController.ShowReason) {
        ShelfPanelController.shared.show(anchor: toggleItem.button, reason: reason)
    }

    /// The activation engine calls this when a target is one of Pelmet's
    /// own collapse-hidden items: reveal the bar so it becomes clickable.
    func expandForActivation() {
        guard isCollapsed else { return }
        expand(scheduleRehide: false)
    }

    /// Pelmet's own status-item window frames — excluded from activation
    /// targets and drag neighbors.
    var ownItemFrames: [CGRect] {
        [separatorItem?.button?.window?.frame, toggleItem?.button?.window?.frame]
            .compactMap { $0 }
    }

    /// State is conveyed by the chevron glyph and a plain-text count ONLY —
    /// never a colored dot. Small colored dots in the menu bar are macOS
    /// privacy vocabulary (green = camera, orange = mic, purple = screen
    /// capture) and a badge in that grammar reads as a recording alarm.
    private func updateToggleIcon() {
        guard let button = toggleItem.button else { return }

        let symbol = isCollapsed ? "chevron.left" : "chevron.right"
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: isCollapsed ? "Show hidden icons" : "Hide icons"
        )

        let showCount = !isCollapsed && swallowedCount > 0 && Preferences.showSwallowedCount
        if showCount {
            button.attributedTitle = NSAttributedString(
                string: "+\(swallowedCount)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }

        let tooltip: String
        let accessibilityValue: String
        if isCollapsed {
            tooltip = "Pelmet: show hidden icons (⌥⌘B)"
            accessibilityValue = "Icons hidden"
        } else if separatorSwallowed {
            tooltip = "The menu bar is full. Pelmet's divider is hidden by the notch. Right-click for options."
            accessibilityValue = "Icons shown. The divider is hidden; the menu bar is full."
        } else if swallowedCount > 0 {
            // "Click to see them" only when a click actually opens the Shelf
            // — i.e. the badge is visible (showCount) and the Shelf is on.
            if showCount && Preferences.shelfEnabled {
                tooltip = "\(countPhrase(swallowedCount)) by the notch. Click to see them; right-click for options."
                accessibilityValue = "Icons shown. \(countPhrase(swallowedCount)) by the notch. Click to open the Shelf."
            } else {
                tooltip = "\(countPhrase(swallowedCount)) by the notch. Right-click for ways to make room."
                accessibilityValue = "Icons shown. \(countPhrase(swallowedCount)) by the notch."
            }
        } else {
            tooltip = "Pelmet: hide icons (⌥⌘B)"
            accessibilityValue = "Icons shown"
        }
        button.toolTip = tooltip
        button.setAccessibilityValue(accessibilityValue)
    }

    private func countPhrase(_ count: Int) -> String {
        count == 1
            ? "1 icon doesn't fit and is hidden"
            : "\(count) icons don't fit and are hidden"
    }

    private func separatorImage() -> NSImage? {
        NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Pelmet divider")
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Status section — present only when there is something to say
        // (disabled informational rows, the Wi-Fi-menu pattern).
        var statusLines: [String] = []
        if separatorSwallowed {
            statusLines.append("Pelmet's divider is hidden; the menu bar is full")
        }
        if swallowedCount > 0 {
            let fitPhrase = swallowedCount == 1 ? "1 icon doesn't fit" : "\(swallowedCount) icons don't fit"
            statusLines.append(
                isCollapsed
                    ? "\(fitPhrase) even while collapsed"
                    : "\(fitPhrase), hidden by the notch"
            )
        }
        if !statusLines.isEmpty {
            for line in statusLines {
                let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
            let hint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            hint.attributedTitle = NSAttributedString(
                string: "⌘-drag important icons toward the clock,\nor quit unused menu bar apps.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            menu.addItem(hint)

            if swallowedCount > 0 {
                // Always offered while something is hidden — the menu is the
                // path that works even with the click-to-open pref off.
                let shelfEntry = NSMenuItem(
                    title: "See What's Hidden…",
                    action: #selector(openShelfFromMenu),
                    keyEquivalent: "n"
                )
                shelfEntry.keyEquivalentModifierMask = [.command, .option]
                shelfEntry.target = self
                menu.addItem(shelfEntry)
            }

            let makeRoomEntry = NSMenuItem(
                title: "Make Room…",
                action: #selector(openMakeRoom),
                keyEquivalent: ""
            )
            makeRoomEntry.target = self
            menu.addItem(makeRoomEntry)

            menu.addItem(.separator())
        }

        let toggleTitle = isCollapsed ? "Show Hidden Icons" : "Hide Icons"
        let toggleEntry = NSMenuItem(title: toggleTitle, action: #selector(menuToggle), keyEquivalent: "b")
        toggleEntry.keyEquivalentModifierMask = [.command, .option]
        toggleEntry.target = self
        menu.addItem(toggleEntry)

        menu.addItem(.separator())

        let resetEntry = NSMenuItem(
            title: "Reset Divider Position",
            action: #selector(resetDividerPosition),
            keyEquivalent: ""
        )
        resetEntry.target = self
        menu.addItem(resetEntry)

        // A permanent path to enable one-click open — survives a dismissed or
        // never-seen onboarding popover. Only where it's relevant (notched Mac,
        // not yet granted).
        if LayoutStatus.shared.hasNotchedDisplay, shelfEngine.availability != .granted {
            let oneClickEntry = NSMenuItem(
                title: "Open Hidden Icons with One Click…",
                action: #selector(enableOneClickFromMenu),
                keyEquivalent: ""
            )
            oneClickEntry.target = self
            menu.addItem(oneClickEntry)
        }

        let settingsEntry = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsEntry.target = self
        menu.addItem(settingsEntry)

        menu.addItem(.separator())

        let quitEntry = NSMenuItem(title: "Quit Pelmet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitEntry)

        NotchLayoutMonitor.shared.requestMeasurement(reason: .menuOpened)

        // Standard trick: temporarily attach the menu, click, detach —
        // keeps left-click free for the toggle action.
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func menuToggle() { toggle() }

    @objc private func enableOneClickFromMenu() {
        shelfEngine.offerOneClick(proactive: false)
    }

    /// Escape hatch for a divider ⌘-dragged somewhere invisible (under the
    /// notch, or off among icons the user can't find): recreate it in the
    /// seeded spot next to the toggle.
    @objc private func resetDividerPosition() {
        let wasCollapsed = isCollapsed
        separatorItem = StatusItemRescuer.recreate(
            separatorItem,
            autosaveName: separatorAutosaveName,
            length: wasCollapsed ? collapsedSeparatorLength : expandedSeparatorLength,
            preferredPosition: 1,
            configure: { [weak self] item in self?.configureSeparatorButton(item) }
        )
        if wasCollapsed {
            separatorItem.button?.image = nil
        }
        NotchLayoutMonitor.shared.reattach(separator: separatorItem, toggle: toggleItem)
    }

    // MARK: - Auto-rehide

    private func scheduleRehideIfNeeded() {
        rehideTimer?.invalidate()
        guard Preferences.autoRehide,
              UIActivityTracker.shared.openSurfaces == 0 else { return }
        rehideTimer = Timer.scheduledTimer(
            withTimeInterval: Preferences.rehideDelay,
            repeats: false
        ) { [weak self] _ in
            self?.collapse()
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openMakeRoom() {
        MakeRoomWindowController.shared.show()
    }
}
