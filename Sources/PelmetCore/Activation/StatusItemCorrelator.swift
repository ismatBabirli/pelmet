import CoreGraphics
import Foundation

/// One status item as an identity source observed it (AX sweep or CGWindow
/// owner) — pure value type, AppKit coordinates.
public struct ItemObservation: Equatable {
    public let pid: Int32
    public let title: String?
    /// nil when the source couldn't read a position.
    public let frame: CGRect?

    public init(pid: Int32, title: String?, frame: CGRect?) {
        self.pid = pid
        self.title = title
        self.frame = frame
    }
}

/// Merges identity observations onto classifier output. The classifier's
/// frames stay the single source of truth for geometry and visibility;
/// observations only contribute identity.
public enum StatusItemCorrelator {

    /// Two frames must overlap horizontally by at least this fraction of
    /// the narrower one to be the same item.
    public static let minOverlapFraction: CGFloat = 0.5

    /// Greedy best-overlap matching: strongest (overlap, then closest
    /// midX) pairs win; each observation is used at most once. Items with
    /// no qualifying observation get nil. Frameless observations never
    /// match (there is nothing to correlate on).
    public static func correlate(
        classified: [ClassifiedItem],
        observed: [ItemObservation]
    ) -> [(item: ClassifiedItem, observation: ItemObservation?)] {
        struct Candidate {
            let itemIndex: Int
            let observationIndex: Int
            let overlap: CGFloat
            let midXDelta: CGFloat
        }

        var candidates: [Candidate] = []
        for (itemIndex, item) in classified.enumerated() {
            for (observationIndex, observation) in observed.enumerated() {
                guard let frame = observation.frame else { continue }
                let overlap = min(item.frame.maxX, frame.maxX) - max(item.frame.minX, frame.minX)
                let narrower = min(item.frame.width, frame.width)
                guard narrower > 0, overlap >= narrower * minOverlapFraction else { continue }
                candidates.append(Candidate(
                    itemIndex: itemIndex,
                    observationIndex: observationIndex,
                    overlap: overlap,
                    midXDelta: abs(item.frame.midX - frame.midX)
                ))
            }
        }
        candidates.sort {
            $0.overlap != $1.overlap ? $0.overlap > $1.overlap : $0.midXDelta < $1.midXDelta
        }

        var observationForItem = [Int: Int]()
        var usedObservations = Set<Int>()
        for candidate in candidates {
            guard observationForItem[candidate.itemIndex] == nil,
                  !usedObservations.contains(candidate.observationIndex) else { continue }
            observationForItem[candidate.itemIndex] = candidate.observationIndex
            usedObservations.insert(candidate.observationIndex)
        }

        return classified.enumerated().map { index, item in
            (item: item, observation: observationForItem[index].map { observed[$0] })
        }
    }
}
