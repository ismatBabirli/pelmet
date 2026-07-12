import CoreGraphics
import Foundation

/// Owner metadata the app layer resolves from NSRunningApplication.
/// Pure value type — no NSImage here; icons stay in the app layer.
public struct RunningAppInfo: Equatable {
    public let pid: Int32
    public let bundleID: String?
    public let localizedName: String?

    public init(pid: Int32, bundleID: String?, localizedName: String?) {
        self.pid = pid
        self.bundleID = bundleID
        self.localizedName = localizedName
    }
}

/// What the Accessibility engine hands the deriver for enrichment — a pure
/// descriptor of one activatable item. Empty array when the engine is
/// absent or not authorized.
public struct EngineItemDescriptor: Equatable {
    /// Opaque activation handle, engine-owned (a MenuBarItemRecord id).
    public let token: String
    /// nil when the engine has no meaningful name for the item — the
    /// deriver falls back to app name or a numbered "Hidden item N".
    public let title: String?
    public let ownerPID: Int32?
    /// AppKit screen coordinates; nil when the AX position was unavailable.
    public let frame: CGRect?

    public init(token: String, title: String?, ownerPID: Int32?, frame: CGRect?) {
        self.token = token
        self.title = title
        self.ownerPID = ownerPID
        self.frame = frame
    }
}

/// One row of the Shelf.
public struct ShelfEntryModel: Equatable, Identifiable {
    public enum Kind: Equatable {
        /// Owner resolved without the engine (≤ Sequoia: CGWindow owner).
        /// `itemCount > 1` means consecutive items of the same app were
        /// grouped into this one row.
        case app(pid: Int32, name: String, itemCount: Int)
        /// Ownership unknown (Tahoe without the engine: every window is
        /// Control Center's). `ordinal` is 1-based, left to right.
        case unknown(ordinal: Int)
        /// Engine-enriched: real title + activation token.
        case engineItem(token: String, title: String, ownerPID: Int32?)
    }

    public let id: String
    public let kind: Kind
    /// The real menu-bar frame (leftmost member for grouped rows) — the
    /// left-to-right sort key, and where activation ultimately lands.
    public let frame: CGRect

    public init(id: String, kind: Kind, frame: CGRect) {
        self.id = id
        self.kind = kind
        self.frame = frame
    }
}

/// Pure derivation of Shelf rows from a layout classification.
///
/// Source-of-truth rule (badge parity): the rows are exactly the
/// classification's `.swallowedByNotch` items — the same set the "+N" badge
/// counts. Engine items only ENRICH rows (title, activation token); they
/// never add or remove any.
public enum ShelfContentDeriver {

    /// Engine frames must land within this of a classified item's midX to
    /// enrich it.
    public static let frameMatchTolerance: CGFloat = 8

    public static func derive(
        classification: LayoutClassification,
        apps: [Int32: RunningAppInfo],
        controlCenterPID: Int32?,
        ownPID: Int32,
        engineItems: [EngineItemDescriptor]
    ) -> [ShelfEntryModel] {
        let swallowed = classification.items
            .filter { $0.visibility == .swallowedByNotch }
            // Defensively drop Pelmet's own windows if frame exclusion ever
            // slips — better a missing row than Pelmet listing itself.
            .filter { !$0.ownerPIDs.contains(ownPID) }
            .sorted { $0.frame.minX < $1.frame.minX }

        guard !swallowed.isEmpty else { return [] }

        // Owner = first PID that isn't the Control Center mirror. On Tahoe
        // every window is Control-Center-owned, so this yields nil there —
        // anonymity is emergent from the data, not an OS version check.
        let owners: [Int32?] = swallowed.map { item in
            item.ownerPIDs.first { $0 != controlCenterPID }
        }

        // Enrichment pass 1: match engine descriptors to items by frame.
        var descriptorForItem = [Int: EngineItemDescriptor]()
        var unmatched = engineItems
        for (index, item) in swallowed.enumerated() {
            guard let match = unmatched.firstIndex(where: { descriptor in
                guard let frame = descriptor.frame else { return false }
                return abs(frame.midX - item.frame.midX) <= frameMatchTolerance
            }) else { continue }
            descriptorForItem[index] = unmatched.remove(at: match)
        }
        // Pass 2: frameless descriptors match by owner PID when both sides
        // are unambiguous (exactly one unenriched item and one descriptor
        // for that PID).
        for descriptor in unmatched where descriptor.frame == nil {
            guard let pid = descriptor.ownerPID else { continue }
            let itemIndices = swallowed.indices.filter {
                owners[$0] == pid && descriptorForItem[$0] == nil
            }
            let twins = engineItems.filter { $0.frame == nil && $0.ownerPID == pid }
            if itemIndices.count == 1, twins.count == 1 {
                descriptorForItem[itemIndices[0]] = descriptor
            }
        }
        // Descriptors with no classified counterpart are dropped: badge parity.

        var entries: [ShelfEntryModel] = []
        var unknownOrdinal = 0
        for (index, item) in swallowed.enumerated() {
            if let descriptor = descriptorForItem[index] {
                // Engine rows still deserve the best available name: real
                // title → owning app's name → numbered fallback (same
                // numbering the anonymous tier uses).
                let ownerPID = descriptor.ownerPID ?? owners[index]
                let title: String
                if let real = descriptor.title {
                    title = real
                } else if let pid = ownerPID, let info = apps[pid],
                          let name = info.localizedName ?? info.bundleID {
                    title = name
                } else {
                    unknownOrdinal += 1
                    title = "Hidden item \(unknownOrdinal)"
                }
                entries.append(ShelfEntryModel(
                    id: "engine-\(descriptor.token)",
                    kind: .engineItem(
                        token: descriptor.token,
                        title: title,
                        ownerPID: ownerPID
                    ),
                    frame: item.frame
                ))
                continue
            }
            if let pid = owners[index], let info = apps[pid],
               let name = info.localizedName ?? info.bundleID {
                entries.append(ShelfEntryModel(
                    id: "app-\(pid)-\(index)",
                    kind: .app(pid: pid, name: name, itemCount: 1),
                    frame: item.frame
                ))
                continue
            }
            unknownOrdinal += 1
            entries.append(ShelfEntryModel(
                id: "unknown-\(unknownOrdinal)",
                kind: .unknown(ordinal: unknownOrdinal),
                frame: item.frame
            ))
        }

        // Without engine titles, Tier 0 can't distinguish (or individually
        // activate) two items of the same app — "Dropbox — 2 items" beats
        // two identical "Dropbox" rows. With the engine, never group.
        return engineItems.isEmpty ? groupConsecutiveSameApp(entries) : entries
    }

    private static func groupConsecutiveSameApp(_ entries: [ShelfEntryModel]) -> [ShelfEntryModel] {
        var result: [ShelfEntryModel] = []
        for entry in entries {
            if case .app(let pid, let name, let count) = entry.kind,
               let last = result.last,
               case .app(let lastPID, _, let lastCount) = last.kind,
               pid == lastPID {
                result[result.count - 1] = ShelfEntryModel(
                    id: last.id,
                    kind: .app(pid: pid, name: name, itemCount: lastCount + count),
                    frame: last.frame
                )
            } else {
                result.append(entry)
            }
        }
        return result
    }
}
