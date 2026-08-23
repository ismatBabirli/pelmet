import AppKit
import Combine
import PelmetCore

extension Notification.Name {
    static let pelmetSoftwareIslandConfigurationDidChange = Notification.Name(
        "PelmetSoftwareIslandConfigurationDidChange"
    )
}

/// Permission-free discovery and local configuration for software-drawn
/// menu bar islands. Known providers work automatically. Unknown candidates
/// remain inert until the user enables a local rule in Settings.
final class SoftwareIslandMonitor: ObservableObject {

    struct Candidate: Equatable, Identifiable {
        let bundleIdentifier: String
        let displayName: String
        let screenFrames: [CGRect]
        let outerWindowFrame: CGRect
        let provider: SoftwareIslandProvider?
        let enabled: Bool
        let restingWidth: CGFloat

        var id: String { bundleIdentifier }
        var isKnown: Bool { provider != nil }
    }

    static let shared = SoftwareIslandMonitor()

    @Published private(set) var candidates: [Candidate] = []
    private var detections: [SoftwareIslandDetection] = []

    var hasEnabledCandidate: Bool {
        candidates.contains(where: \.enabled)
    }

    private init() {}

    /// Refreshes the Window Server snapshot exactly once. Callers that only
    /// changed a local rule use rebuildCandidates() instead of rescanning.
    func refresh() {
        detections = WindowListSource.softwareIslandWindows()
        rebuildCandidates()
    }

    private func rebuildCandidates() {
        let rules = Preferences.softwareIslandRules

        let next = SoftwareIslandDetectionGrouper.group(detections).map { group in
            let bundleIdentifier = group.bundleIdentifier
            let provider = SoftwareIslandRegistry.provider(for: bundleIdentifier)
            let rule = rules[bundleIdentifier]
            let defaultWidth = provider?.defaultRestingWidth
                ?? min(group.widestOuterWindowFrame.width, 340)
            return Candidate(
                bundleIdentifier: bundleIdentifier,
                displayName: provider?.displayName ?? group.displayName,
                screenFrames: group.screenFrames,
                outerWindowFrame: group.widestOuterWindowFrame,
                provider: provider,
                enabled: rule?.enabled ?? (provider != nil),
                restingWidth: CGFloat(rule?.restingWidth ?? Double(defaultWidth))
            )
        }
        .sorted {
            if $0.isKnown != $1.isKnown { return $0.isKnown }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        if next != candidates {
            candidates = next
        }
    }

    func obstruction(on screen: NSScreen, menuBarHeight: CGFloat) -> CGRect? {
        guard let candidate = candidates
            .filter({ $0.enabled && $0.screenFrames.contains(screen.frame) })
            .max(by: { $0.restingWidth < $1.restingWidth })
        else { return nil }

        return SoftwareIslandCandidateClassifier.restingRect(
            width: candidate.restingWidth,
            screenFrame: screen.frame,
            menuBarHeight: menuBarHeight
        )
    }

    func preferredScreenFrame(preferred preferredFrame: CGRect?) -> CGRect? {
        let enabledFrames = candidates
            .filter(\.enabled)
            .flatMap(\.screenFrames)
        if let preferredFrame, enabledFrames.contains(preferredFrame) {
            return preferredFrame
        }
        return enabledFrames.first
    }

    func setEnabled(_ enabled: Bool, for candidate: Candidate) {
        Preferences.updateSoftwareIslandRule(
            bundleIdentifier: candidate.bundleIdentifier,
            enabled: enabled
        )
        configurationChanged()
    }

    func setRestingWidth(_ restingWidth: CGFloat, for candidate: Candidate) {
        Preferences.updateSoftwareIslandRule(
            bundleIdentifier: candidate.bundleIdentifier,
            restingWidth: restingWidth
        )
        configurationChanged()
    }

    private func configurationChanged() {
        rebuildCandidates()
        NotificationCenter.default.post(
            name: .pelmetSoftwareIslandConfigurationDidChange,
            object: self
        )
    }
}
