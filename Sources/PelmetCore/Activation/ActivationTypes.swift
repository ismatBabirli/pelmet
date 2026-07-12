import CoreGraphics
import Foundation

/// Whether the Accessibility-gated activation engine may act. TCC exposes no
/// notDetermined/denied distinction, so the split is reconstructed from
/// "feature enabled" + "did we ever trigger the prompt" + `AXIsProcessTrusted`.
public enum ActivationAvailability: Equatable {
    /// Feature never enabled, or enabled but the system prompt never shown.
    case notDetermined
    /// Enabled and prompted, but the app is not trusted (declined/revoked).
    case denied
    case granted
}

/// Hygiene filter for AX titles: many apps expose junk internal identifiers
/// ("menubaricon_v3", bundle ids, UUIDs). Only titles that look like words
/// a human wrote are worth showing over the app name.
public enum TitleHygiene {
    public static func meaningfulTitle(
        _ raw: String?,
        appName: String,
        bundleID: String?
    ) -> String? {
        guard let raw else { return nil }
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.count <= 40,
              title.rangeOfCharacter(from: .letters) != nil,
              title.caseInsensitiveCompare(appName) != .orderedSame,
              title != bundleID,
              !title.contains("_"),
              // Reverse-DNS-ish strings are identifiers, not titles.
              title.filter({ $0 == "." }).count < 2
        else { return nil }
        return title
    }
}

/// Who owns a status item, as far as any data source could tell.
public struct ItemIdentity: Equatable {
    public let pid: Int32
    public let bundleIdentifier: String?
    /// Display string — always prefer this; AX titles are often junk
    /// internal identifiers.
    public let appName: String
    /// Surfaced only when it passed the "meaningful title" hygiene filter.
    public let axTitle: String?

    public init(pid: Int32, bundleIdentifier: String?, appName: String, axTitle: String?) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.axTitle = axTitle
    }
}

/// How much the current directory actually knows.
public enum DirectoryFidelity: Equatable {
    /// Frames + visibility only — no trustworthy ownership (Tahoe without
    /// the Accessibility grant, or a future macOS that broke both sources).
    case framesOnly
    /// Ownership available (CGWindow owner on ≤ Sequoia, or the AX sweep).
    case identified
}

/// One status item the engine knows about: classifier geometry + optional
/// identity.
public struct MenuBarItemRecord: Identifiable, Equatable {
    public let id: String
    /// Classifier frame, AppKit screen coordinates.
    public let frame: CGRect
    public let visibility: ItemVisibility
    public let identity: ItemIdentity?

    public init(frame: CGRect, visibility: ItemVisibility, identity: ItemIdentity?) {
        self.id = MenuBarItemRecord.makeID(frame: frame, pid: identity?.pid)
        self.frame = frame
        self.visibility = visibility
        self.identity = identity
    }

    /// Stable across re-measurements of an unmoved item: PID plus rounded
    /// midX (identity survives small frame jitter via the rounding).
    public static func makeID(frame: CGRect, pid: Int32?) -> String {
        let midX = Int((frame.midX / 4).rounded()) * 4
        if let pid { return "\(pid):\(midX)" }
        return "frame:\(midX)x\(Int(frame.width.rounded()))"
    }
}

public struct DirectorySnapshot: Equatable {
    public let records: [MenuBarItemRecord]
    public let fidelity: DirectoryFidelity
    public let capturedAt: Date

    public init(records: [MenuBarItemRecord], fidelity: DirectoryFidelity, capturedAt: Date) {
        self.records = records
        self.fidelity = fidelity
        self.capturedAt = capturedAt
    }

    public static let empty = DirectorySnapshot(records: [], fidelity: .framesOnly, capturedAt: .distantPast)
}

/// Whether an activation was confirmed to have opened something.
public enum ActivationVerification: Equatable {
    case menuOpened
    /// The final click was posted but no new menu window was detected —
    /// reported as soft success (many items open panels we can't classify).
    case unverified
}

public enum ActivationFailure: Equatable {
    case permissionDenied
    case itemVanished
    /// The item sits in the notch dead zone and no strategy got through.
    case blockedByNotch
    /// No visible neighbor could be moved to make room.
    case noRoomToExpose
    /// Another activation is already in flight (or rate-limited).
    case busy
    /// The user is mid-drag/mid-click; refusing to fight them.
    case userInteracting
    /// Space change, screen lock, or session resign mid-flight.
    case interrupted
    case timedOut
}

public enum ActivationResult: Equatable {
    case activated(ActivationVerification)
    case failed(ActivationFailure)
}
