import AppKit

/// Manages two NSStatusItems:
///
///  ┌────────────────────────── menu bar ──────────────────────────┐
///  │  [hidden icons...]  |separator|  [always-visible icons...] [toggle]  clock │
///  └───────────────────────────────────────────────────────────────┘
///
/// Anything the user ⌘-drags to the LEFT of the separator is controlled
/// by Pelmet. When collapsed, the separator's length is inflated to a
/// huge value, pushing everything left of it off the screen edge —
/// the same technique used by Hidden Bar / Dozer. No private APIs,
/// no Screen Recording or Accessibility permission required.
final class MenuBarManager: NSObject {

    static let shared = MenuBarManager()

    // MARK: - Configuration

    private let expandedSeparatorLength: CGFloat = 10
    /// Large enough to push items past the left screen edge on any display.
    private let collapsedSeparatorLength: CGFloat = 10_000

    private let toggleAutosaveName = "Pelmet_Toggle"
    private let separatorAutosaveName = "Pelmet_Separator"

    // MARK: - State

    private(set) var isCollapsed = false
    private var rehideTimer: Timer?

    private var toggleItem: NSStatusItem!
    private var separatorItem: NSStatusItem!

    // MARK: - Setup

    func setUp() {
        seedFirstLaunchPositionIfNeeded()

        // Creation order matters only for the very first launch;
        // autosaveName persists whatever arrangement the user ⌘-drags into.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = toggleAutosaveName
        toggleItem.behavior = []
        // Assigning autosaveName adopts persisted state, so un-hide AFTER it —
        // recovers an item ⌘-dragged out of the bar by an earlier build.
        toggleItem.isVisible = true

        separatorItem = NSStatusBar.system.statusItem(withLength: expandedSeparatorLength)
        separatorItem.autosaveName = separatorAutosaveName
        separatorItem.isVisible = true

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Pelmet — click to show/hide menu bar items (⌥⌘B)"
        }

        if let button = separatorItem.button {
            button.image = separatorImage()
            button.appearsDisabled = true
            button.toolTip = "⌘-drag icons to the LEFT of this divider to let Pelmet manage them"
        }

        // Restore the last collapse state. First launch starts EXPANDED:
        // collapsing would hide nothing (no icons are managed yet) while
        // turning the ╱ divider into an invisible 10,000 pt spacer.
        Preferences.isCollapsed ? collapse() : expand()
    }

    /// macOS stores each status item's position in UserDefaults under
    /// "NSStatusItem Preferred Position <autosaveName>" — the distance in
    /// points from the RIGHT screen edge (larger = further left). Undocumented
    /// but stable since 10.12; Hidden Bar and Ice rely on it. Without a seed,
    /// a brand-new item is inserted at the LEFT end of the item area — on
    /// notched MacBooks exactly the region macOS silently swallows when the
    /// bar is full, which can make a first launch completely invisible.
    /// Seeding the toggle next to the clock sidesteps that. The separator is
    /// deliberately NOT seeded: it must start left of every existing icon so
    /// that nothing is "managed" (hidden on collapse) until the user opts in
    /// by ⌘-dragging icons across it.
    private func seedFirstLaunchPositionIfNeeded() {
        let key = "NSStatusItem Preferred Position \(toggleAutosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(0, forKey: key)
    }

    // MARK: - Public actions

    func toggle() {
        isCollapsed ? expand() : collapse()
    }

    func expand() {
        isCollapsed = false
        Preferences.isCollapsed = false
        separatorItem.length = expandedSeparatorLength
        separatorItem.button?.image = separatorImage()
        updateToggleIcon()
        scheduleRehideIfNeeded()
    }

    func collapse() {
        isCollapsed = true
        Preferences.isCollapsed = true
        rehideTimer?.invalidate()
        separatorItem.length = collapsedSeparatorLength
        // Hide the divider glyph while it's a giant invisible spacer.
        separatorItem.button?.image = nil
        updateToggleIcon()
    }

    // MARK: - Auto-rehide

    private func scheduleRehideIfNeeded() {
        rehideTimer?.invalidate()
        guard Preferences.autoRehide else { return }
        rehideTimer = Timer.scheduledTimer(
            withTimeInterval: Preferences.rehideDelay,
            repeats: false
        ) { [weak self] _ in
            self?.collapse()
        }
    }

    // MARK: - UI plumbing

    @objc private func toggleButtonClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggle()
        }
    }

    private func updateToggleIcon() {
        let symbol = isCollapsed ? "chevron.left" : "chevron.right"
        toggleItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: isCollapsed ? "Show hidden items" : "Hide items"
        )
    }

    private func separatorImage() -> NSImage? {
        NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Pelmet divider")
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let toggleTitle = isCollapsed ? "Show Hidden Items" : "Hide Items"
        let toggleEntry = NSMenuItem(title: toggleTitle, action: #selector(menuToggle), keyEquivalent: "b")
        toggleEntry.keyEquivalentModifierMask = [.command, .option]
        toggleEntry.target = self
        menu.addItem(toggleEntry)

        menu.addItem(.separator())

        let settingsEntry = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsEntry.target = self
        menu.addItem(settingsEntry)

        menu.addItem(.separator())

        let quitEntry = NSMenuItem(title: "Quit Pelmet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitEntry)

        // Standard trick: temporarily attach the menu, click, detach —
        // keeps left-click free for the toggle action.
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func menuToggle() { toggle() }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }
}
