import CoreGraphics
import Foundation

/// How Pelmet treats a known software island when its host window grows.
/// Resting-only providers keep a stable menu bar reservation while transient
/// hover panels are open, so status items do not jump under the pointer.
public enum SoftwareIslandExpansionPolicy: Equatable {
    case restingWidthOnly
}

/// A source-controlled compatibility hint for a known top-center overlay.
/// Geometry remains user-adjustable because display scaling and app settings
/// can change the visible resting width independently of the outer window.
public struct SoftwareIslandProvider: Equatable {
    public let id: String
    public let displayName: String
    public let bundleIdentifiers: Set<String>
    public let defaultRestingWidth: CGFloat
    public let expansionPolicy: SoftwareIslandExpansionPolicy

    public init(
        id: String,
        displayName: String,
        bundleIdentifiers: Set<String>,
        defaultRestingWidth: CGFloat,
        expansionPolicy: SoftwareIslandExpansionPolicy
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers
        self.defaultRestingWidth = defaultRestingWidth
        self.expansionPolicy = expansionPolicy
    }
}

public enum SoftwareIslandRegistry {

    public static let providers: [SoftwareIslandProvider] = [
        SoftwareIslandProvider(
            id: "vibe-island",
            displayName: "Vibe Island",
            bundleIdentifiers: ["app.vibeisland.macos"],
            // Vibe Island uses a 680 pt transparent envelope. Its resting
            // pill is much narrower and is user-tunable, so this is only the
            // first-run calibration value.
            defaultRestingWidth: 340,
            expansionPolicy: .restingWidthOnly
        ),
    ]

    public static func provider(for bundleIdentifier: String) -> SoftwareIslandProvider? {
        providers.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }
}

/// Permission-free facts about a foreign window, normalized to AppKit screen
/// coordinates before they enter the pure candidate classifier.
public struct SoftwareIslandWindowObservation: Equatable {
    public let frame: CGRect
    public let layer: Int
    public let bundleIdentifier: String
    public let isAccessoryApplication: Bool
    public let isSystemOwner: Bool

    public init(
        frame: CGRect,
        layer: Int,
        bundleIdentifier: String,
        isAccessoryApplication: Bool,
        isSystemOwner: Bool
    ) {
        self.frame = frame
        self.layer = layer
        self.bundleIdentifier = bundleIdentifier
        self.isAccessoryApplication = isAccessoryApplication
        self.isSystemOwner = isSystemOwner
    }
}

/// One locally detected candidate window after the app layer has resolved its
/// display name and screen. Keeping this value pure makes multi-display
/// grouping testable without querying Window Server in tests.
public struct SoftwareIslandDetection: Equatable {
    public let bundleIdentifier: String
    public let displayName: String
    public let screenFrame: CGRect
    public let outerWindowFrame: CGRect

    public init(
        bundleIdentifier: String,
        displayName: String,
        screenFrame: CGRect,
        outerWindowFrame: CGRect
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.screenFrame = screenFrame
        self.outerWindowFrame = outerWindowFrame
    }
}

/// Every detected screen for one app, plus a representative outer envelope
/// used only to choose the initial resting-width calibration.
public struct SoftwareIslandDetectionGroup: Equatable {
    public let bundleIdentifier: String
    public let displayName: String
    public let screenFrames: [CGRect]
    public let widestOuterWindowFrame: CGRect
}

public enum SoftwareIslandDetectionGrouper {

    public static func group(
        _ detections: [SoftwareIslandDetection]
    ) -> [SoftwareIslandDetectionGroup] {
        var byBundleIdentifier: [String: [SoftwareIslandDetection]] = [:]
        for detection in detections {
            byBundleIdentifier[detection.bundleIdentifier, default: []].append(detection)
        }

        return byBundleIdentifier.map { bundleIdentifier, members in
            let representative = members.max(by: representativeSort)!
            let screenFrames = members
                .map(\.screenFrame)
                .reduce(into: [CGRect]()) { result, frame in
                    if !result.contains(frame) { result.append(frame) }
                }
                .sorted(by: screenSort)
            return SoftwareIslandDetectionGroup(
                bundleIdentifier: bundleIdentifier,
                displayName: representative.displayName,
                screenFrames: screenFrames,
                widestOuterWindowFrame: representative.outerWindowFrame
            )
        }
        .sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }

    private static func representativeSort(
        _ lhs: SoftwareIslandDetection,
        _ rhs: SoftwareIslandDetection
    ) -> Bool {
        let left = lhs.outerWindowFrame
        let right = rhs.outerWindowFrame
        if left.width != right.width { return left.width < right.width }
        if left.height != right.height { return left.height < right.height }
        if left.minX != right.minX { return left.minX > right.minX }
        return left.minY > right.minY
    }

    private static func screenSort(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        if lhs.minX != rhs.minX { return lhs.minX < rhs.minX }
        if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
        if lhs.width != rhs.width { return lhs.width < rhs.width }
        return lhs.height < rhs.height
    }
}

/// Conservative generic discovery for persistent notch-style overlays.
/// This identifies candidates, not their opaque pixel shape. Unknown apps
/// still require a local user rule before Pelmet reserves space for them.
public enum SoftwareIslandCandidateClassifier {

    public static let statusItemWindowLevel = 25
    public static let minimumWidth: CGFloat = 80
    public static let maximumScreenWidthFraction: CGFloat = 0.65
    public static let topEdgeTolerance: CGFloat = 2
    public static let centerToleranceFraction: CGFloat = 0.03

    public static func isCandidate(
        _ observation: SoftwareIslandWindowObservation,
        screenFrame: CGRect,
        menuBarHeight: CGFloat
    ) -> Bool {
        let frame = observation.frame
        let centerTolerance = max(4, screenFrame.width * centerToleranceFraction)
        let isKnownProvider = SoftwareIslandRegistry.provider(
            for: observation.bundleIdentifier
        ) != nil

        return observation.layer > statusItemWindowLevel
            && observation.isAccessoryApplication
            && !observation.isSystemOwner
            && frame.intersects(screenFrame)
            && abs(frame.maxY - screenFrame.maxY) <= topEdgeTolerance
            && abs(frame.midX - screenFrame.midX) <= centerTolerance
            && frame.width >= minimumWidth
            && (isKnownProvider
                || frame.width <= screenFrame.width * maximumScreenWidthFraction)
            && frame.height >= max(8, menuBarHeight * 0.8)
    }

    public static func restingRect(
        width requestedWidth: CGFloat,
        screenFrame: CGRect,
        menuBarHeight: CGFloat
    ) -> CGRect {
        let width = min(max(requestedWidth, minimumWidth), screenFrame.width)
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - menuBarHeight,
            width: width,
            height: menuBarHeight
        )
    }
}
