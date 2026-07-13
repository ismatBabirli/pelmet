import AppKit
import Combine
import PelmetCore

/// What the Shelf currently knows how to say about its rows.
enum ShelfTier {
    /// Rows carry app identity (≤ Sequoia CGWindow owners, permission-free).
    case owners
    /// Ownership unknown (Tahoe without the engine grant).
    case anonymous
    /// Engine-enriched rows — one click opens the real item.
    case engine
}

struct ShelfRow: Identifiable, Equatable {
    let model: ShelfEntryModel
    let icon: NSImage?
    var id: String { model.id }

    static func == (lhs: ShelfRow, rhs: ShelfRow) -> Bool {
        lhs.model == rhs.model && lhs.icon === rhs.icon
    }
}

final class ShelfViewModel: ObservableObject {

    @Published private(set) var rows: [ShelfRow] = []
    @Published private(set) var tier: ShelfTier = .owners
    @Published private(set) var engineAvailability: ActivationAvailability = .notDetermined
    /// Row whose inline explanation callout is expanded (Tier 0 clicks).
    @Published var expandedExplanationID: String?
    /// Row whose activation just failed, with the message to show.
    @Published private(set) var inlineFailure: (rowID: String, message: String)?
    /// Keyboard selection; nil until the user arrows into the list.
    @Published private(set) var selectedIndex: Int?

    /// Set by the controller: close the panel (successful activation, Esc).
    var onRequestClose: (() -> Void)?

    private let engine: StatusItemActivating

    init(engine: StatusItemActivating) {
        self.engine = engine
        engineAvailability = engine.availability
    }

    var canOfferEngineOptIn: Bool {
        tier != .engine && engineAvailability != .granted
    }

    /// We asked for Accessibility before but still aren't granted: the OS won't
    /// re-show its modal, so the button must deep-link to System Settings
    /// instead of silently no-op'ing. (`engineAvailability` reads
    /// `.notDetermined` while the engine is off, so lean on the prompt flag.)
    var optInIsBlocked: Bool {
        engineAvailability != .granted && Preferences.didPromptForAccessibility
    }

    func update(entries: [ShelfEntryModel]) {
        rows = entries.map { entry in
            ShelfRow(model: entry, icon: icon(for: entry))
        }
        tier = Self.tier(for: entries)
        engineAvailability = engine.availability
        if let selected = selectedIndex, selected >= rows.count {
            selectedIndex = rows.isEmpty ? nil : rows.count - 1
        }
        if let expanded = expandedExplanationID, !rows.contains(where: { $0.id == expanded }) {
            expandedExplanationID = nil
        }
        if let failure = inlineFailure, !rows.contains(where: { $0.id == failure.rowID }) {
            inlineFailure = nil
        }
    }

    static func tier(for entries: [ShelfEntryModel]) -> ShelfTier {
        if entries.contains(where: { if case .engineItem = $0.kind { return true } else { return false } }) {
            return .engine
        }
        if !entries.isEmpty, entries.allSatisfy({ if case .unknown = $0.kind { return true } else { return false } }) {
            return .anonymous
        }
        return .owners
    }

    // MARK: - Row content helpers

    private func icon(for entry: ShelfEntryModel) -> NSImage? {
        switch entry.kind {
        case .app(let pid, _, _):
            return OwnerResolver.shared.icon(forPID: pid)
        case .engineItem(_, _, let ownerPID):
            return ownerPID.flatMap { OwnerResolver.shared.icon(forPID: $0) }
        case .unknown:
            return nil
        }
    }

    // MARK: - Actions

    func activate(_ row: ShelfRow) {
        inlineFailure = nil
        switch row.model.kind {
        case .engineItem(let token, _, _):
            engine.activate(recordID: token) { [weak self] result in
                guard let self else { return }
                switch result {
                case .activated:
                    self.onRequestClose?()
                case .failed(let failure):
                    self.inlineFailure = (row.id, Self.failureMessage(failure))
                }
            }
        case .app(let pid, _, _):
            // Tier 0: the honest best effort is bringing the app forward,
            // plus the explanation of why the icon itself can't open yet.
            OwnerResolver.shared.activateApp(pid: pid)
            expandedExplanationID = expandedExplanationID == row.id ? nil : row.id
        case .unknown:
            expandedExplanationID = expandedExplanationID == row.id ? nil : row.id
        }
    }

    func offerOptIn() {
        // Explicit tap → enable now; routes to the OS prompt, or to System
        // Settings when the modal won't reappear (see `offerOneClick`).
        engine.offerOneClick(proactive: false)
    }

    static func failureMessage(_ failure: ActivationFailure) -> String {
        switch failure {
        case .permissionDenied:
            return "Pelmet needs the Accessibility permission to open items."
        case .itemVanished:
            return "That icon just disappeared. It may have been closed."
        case .blockedByNotch, .noRoomToExpose:
            return "Couldn't open it. The bar is too full. Try Make Room."
        case .busy, .userInteracting:
            return "Busy. Try again in a moment."
        case .interrupted, .timedOut:
            return "Couldn't open it. Try again."
        }
    }

    // MARK: - Keyboard

    /// Returns true when the key was consumed.
    func handle(_ command: ShelfPanel.KeyCommand) -> Bool {
        switch command {
        case .moveUp:
            guard !rows.isEmpty else { return false }
            selectedIndex = max((selectedIndex ?? rows.count) - 1, 0)
            return true
        case .moveDown:
            guard !rows.isEmpty else { return false }
            selectedIndex = min((selectedIndex ?? -1) + 1, rows.count - 1)
            return true
        case .activate:
            guard let index = selectedIndex, rows.indices.contains(index) else { return false }
            activate(rows[index])
            return true
        case .cancel:
            onRequestClose?()
            return true
        }
    }
}
