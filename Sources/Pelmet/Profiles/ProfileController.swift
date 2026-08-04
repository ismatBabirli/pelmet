import AppKit
import Combine
import PelmetCore

struct ProfileOperationContext {
    let wasCollapsed: Bool
}

struct ProfileBarSnapshot {
    let candidates: [ProfileItemCandidate]
    let unidentifiedCount: Int
}

/// Coordinates profile persistence, layout capture, and Accessibility-gated
/// command drags. All public methods are main-thread operations; synthetic
/// events are delegated to MenuBarManager and never run on the main thread.
final class ProfileController: ObservableObject {

    static let shared = ProfileController()

    @Published private(set) var profiles: [MenuBarProfile]
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var defaultProfileID: UUID?
    @Published private(set) var applyDefaultAtLaunch: Bool
    @Published private(set) var isBusy = false
    @Published private(set) var lastResult: ProfileApplyResult?
    @Published private(set) var lastMessage: String?

    private var observedDefaults: NSObjectProtocol?
    private var isPersisting = false

    private init() {
        profiles = Preferences.menuBarProfiles
        activeProfileID = Preferences.activeProfileID
        defaultProfileID = Preferences.defaultProfileID
        applyDefaultAtLaunch = Preferences.applyDefaultProfileAtLaunch
        observedDefaults = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observedDefaults {
            NotificationCenter.default.removeObserver(observedDefaults)
        }
    }

    var activeProfile: MenuBarProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    var defaultProfile: MenuBarProfile? {
        guard let defaultProfileID else { return nil }
        return profiles.first { $0.id == defaultProfileID }
    }

    func reload() {
        guard !isPersisting else { return }
        let savedProfiles = Preferences.menuBarProfiles
        let validIDs = Set(savedProfiles.map(\.id))
        profiles = savedProfiles
        activeProfileID = Preferences.activeProfileID.flatMap { validIDs.contains($0) ? $0 : nil }
        defaultProfileID = Preferences.defaultProfileID.flatMap { validIDs.contains($0) ? $0 : nil }
        applyDefaultAtLaunch = Preferences.applyDefaultProfileAtLaunch && defaultProfileID != nil
    }

    func createFromCurrent(
        name rawName: String,
        completion: @escaping (String) -> Void
    ) {
        let name = normalizedName(rawName)
        guard !name.isEmpty else {
            return completion("Enter a name for this profile.")
        }
        guard !isBusy else {
            return completion("Pelmet is already working on a profile.")
        }

        isBusy = true
        MenuBarManager.shared.beginProfileOperation { [weak self] context, classification in
            guard let self else { return }
            guard let classification else {
                MenuBarManager.shared.endProfileOperation(context)
                self.finishBusy(message: "Pelmet could not confirm the current menu bar layout.")
                return completion(self.lastMessage ?? "")
            }

            MenuBarManager.shared.shelfEngine.requestProfileDirectory { directory in
                let snapshot = MenuBarManager.shared.profileSnapshot(
                    using: classification,
                    directory: directory
                )
                guard !snapshot.candidates.isEmpty else {
                    MenuBarManager.shared.endProfileOperation(context)
                    let message = snapshot.unidentifiedCount > 0
                        ? "No identifiable menu bar items were available. Accessibility may be needed on this macOS version."
                        : "No menu bar items were available to save."
                    self.finishBusy(message: message)
                    return completion(message)
                }

                let placements = snapshot.candidates.map {
                    ProfileItemPlacement(
                        key: $0.key,
                        displayName: $0.displayName,
                        side: $0.side,
                        order: $0.order
                    )
                }
                let profile = MenuBarProfile(name: name, placements: placements)
                self.profiles.append(profile)
                self.activeProfileID = profile.id
                self.persist()
                MenuBarManager.shared.endProfileOperation(context)

                var message = "Saved \(profile.name)."
                if snapshot.unidentifiedCount > 0 {
                    message += " \(snapshot.unidentifiedCount) unidentified item"
                        + (snapshot.unidentifiedCount == 1 ? " was" : "s were")
                        + " left out."
                }
                self.finishBusy(message: message)
                completion(message)
            }
        }
    }

    func rename(_ profileID: UUID, to rawName: String) -> Bool {
        let name = normalizedName(rawName)
        guard !name.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == profileID })
        else { return false }
        profiles[index].name = name
        persist()
        return true
    }

    func delete(_ profileID: UUID) {
        profiles.removeAll { $0.id == profileID }
        if activeProfileID == profileID {
            activeProfileID = profiles.first?.id
        }
        if defaultProfileID == profileID {
            defaultProfileID = nil
            applyDefaultAtLaunch = false
        }
        persist()
    }

    func move(_ profileID: UUID, by offset: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let destination = min(max(index + offset, 0), profiles.count - 1)
        guard destination != index else { return }
        let profile = profiles.remove(at: index)
        profiles.insert(profile, at: destination)
        persist()
    }

    func setActive(_ profileID: UUID?) {
        guard profileID == nil || profiles.contains(where: { $0.id == profileID }) else { return }
        activeProfileID = profileID
        persist()
    }

    func setDefault(_ profileID: UUID?) {
        guard profileID == nil || profiles.contains(where: { $0.id == profileID }) else { return }
        defaultProfileID = profileID
        if profileID == nil {
            applyDefaultAtLaunch = false
        }
        persist()
    }

    func setApplyDefaultAtLaunch(_ enabled: Bool) {
        applyDefaultAtLaunch = enabled && defaultProfileID != nil
        persist()
    }

    /// Called after the menu bar and activation engine are initialized. This
    /// never asks for Accessibility; the result is visible when Settings opens.
    func scheduleDefaultProfileApplication() {
        guard applyDefaultAtLaunch, let defaultProfileID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self,
                  self.applyDefaultAtLaunch,
                  self.defaultProfileID == defaultProfileID
            else { return }
            self.apply(defaultProfileID, reason: .launch) { _ in }
        }
    }

    func apply(
        _ profileID: UUID,
        reason: ProfileApplyReason = .user,
        completion: @escaping (ProfileApplyResult) -> Void
    ) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            let result = ProfileApplyResult(
                profileID: profileID,
                profileName: "Profile",
                appliedCount: 0,
                skippedCount: 0,
                failed: true
            )
            lastResult = result
            lastMessage = result.summary
            return completion(result)
        }
        guard !isBusy else {
            let result = ProfileApplyResult(
                profileID: profile.id,
                profileName: profile.name,
                appliedCount: 0,
                skippedCount: 0,
                failed: true
            )
            lastResult = result
            lastMessage = "Pelmet is already working on a profile."
            return completion(result)
        }

        if ProcessInfo.processInfo.environment["PELMET_DISABLE_ACTIVATION"] == "1" {
            let result = ProfileApplyResult(
                profileID: profile.id,
                profileName: profile.name,
                appliedCount: 0,
                skippedCount: 0,
                failed: true
            )
            lastResult = result
            lastMessage = result.summary
            return completion(result)
        }

        guard StatusItemActivationEngine.shared.canArrangeProfiles else {
            let result = ProfileApplyResult(
                profileID: profile.id,
                profileName: profile.name,
                appliedCount: 0,
                skippedCount: 0,
                missing: profile.placements,
                permissionRequired: true
            )
            lastResult = result
            lastMessage = result.summary
            return completion(result)
        }

        isBusy = true
        MenuBarManager.shared.beginProfileOperation { [weak self] context, classification in
            guard let self else { return }
            guard let classification else {
                MenuBarManager.shared.endProfileOperation(context)
                let result = ProfileApplyResult(
                    profileID: profile.id,
                    profileName: profile.name,
                    appliedCount: 0,
                    skippedCount: 0,
                    failed: true
                )
                self.finish(result: result)
                completion(result)
                return
            }

            MenuBarManager.shared.shelfEngine.requestProfileDirectory { directory in
                let snapshot = MenuBarManager.shared.profileSnapshot(
                    using: classification,
                    directory: directory
                )
                let match = ProfileMatcher.match(profile: profile, candidates: snapshot.candidates)
                guard !match.matches.isEmpty else {
                    MenuBarManager.shared.endProfileOperation(context)
                    let result = ProfileApplyResult(
                        profileID: profile.id,
                        profileName: profile.name,
                        appliedCount: 0,
                        skippedCount: snapshot.unidentifiedCount,
                        missing: match.missing,
                        ambiguous: match.ambiguous
                    )
                    self.finish(result: result)
                    completion(result)
                    return
                }

                self.applyMatches(
                    profile: profile,
                    context: context,
                    initialMatch: match,
                    initialSkipped: snapshot.unidentifiedCount,
                    reason: reason,
                    completion: completion
                )
            }
        }
    }

    private func applyMatches(
        profile: MenuBarProfile,
        context: ProfileOperationContext,
        initialMatch: ProfileMatchResult,
        initialSkipped: Int,
        reason: ProfileApplyReason,
        completion: @escaping (ProfileApplyResult) -> Void
    ) {
        var pending = Set(initialMatch.matches.map { $0.placement.key })
        var appliedCount = 0
        var skippedCount = initialSkipped
        var lastMatch = initialMatch

        func finish(_ failed: Bool = false) {
            MenuBarManager.shared.endProfileOperation(context)
            let result = ProfileApplyResult(
                profileID: profile.id,
                profileName: profile.name,
                appliedCount: appliedCount,
                skippedCount: skippedCount,
                missing: lastMatch.missing,
                ambiguous: lastMatch.ambiguous,
                failed: failed
            )
            if appliedCount > 0 || result.isComplete {
                activeProfileID = profile.id
                persist()
            }
            self.finish(result: result)
            completion(result)
        }

        func step() {
            guard let classification = NotchLayoutMonitor.shared.confirmed else {
                return finish(true)
            }
            MenuBarManager.shared.shelfEngine.requestProfileDirectory { directory in
                let current = MenuBarManager.shared.profileSnapshot(
                    using: classification,
                    directory: directory
                )
                let currentMatch = ProfileMatcher.match(profile: profile, candidates: current.candidates)
                lastMatch = currentMatch

                if self.arrangementMatches(profile: profile, match: currentMatch) {
                    pending.removeAll()
                    return finish()
                }

                guard !pending.isEmpty else { return finish(true) }

                guard let nextPlacement = profile.placements
                    .filter({ pending.contains($0.key) })
                    .sorted(by: { $0.order > $1.order })
                    .first
                else { return finish() }

                guard let match = currentMatch.matches.first(where: {
                    $0.placement.key == nextPlacement.key
                }) else {
                    pending.remove(nextPlacement.key)
                    skippedCount += 1
                    return step()
                }

                let sameSide = match.candidate.side == nextPlacement.side
                let rightNeighbor = profile.placements
                    .filter { placement in
                        placement.side == nextPlacement.side
                            && placement.order > nextPlacement.order
                            && currentMatch.matches.contains { match in
                                match.placement.key == placement.key
                            }
                    }
                    .sorted { $0.order < $1.order }
                    .compactMap { placement in
                        currentMatch.matches.first { $0.placement.key == placement.key }?.candidate
                    }
                    .first

                guard let target = MenuBarManager.shared.profileTargetPoint(
                    side: nextPlacement.side,
                    rightNeighbor: rightNeighbor
                ) else {
                    pending.remove(nextPlacement.key)
                    skippedCount += 1
                    return step()
                }

                let source = CGPoint(x: match.candidate.frame.midX, y: match.candidate.frame.midY)
                pending.remove(nextPlacement.key)

                if sameSide, abs(source.x - target.x) < 4 {
                    appliedCount += 1
                    return step()
                }

                MenuBarManager.shared.performProfileDrag(from: source, to: target) { success in
                    if success {
                        appliedCount += 1
                    } else {
                        skippedCount += 1
                    }
                    NotchLayoutMonitor.shared.requestConfirmedLayout { classification in
                        guard classification != nil else { return finish(true) }
                        step()
                    }
                }
            }
        }

        _ = reason
        step()
    }

    private func arrangementMatches(
        profile: MenuBarProfile,
        match: ProfileMatchResult
    ) -> Bool {
        let matchedKeys = Set(match.matches.map { $0.placement.key })
        guard match.matches.allSatisfy({ $0.candidate.side == $0.placement.side }) else {
            return false
        }

        for side in ProfileItemSide.allCases {
            let desired = profile.placements
                .filter { $0.side == side && matchedKeys.contains($0.key) }
                .sorted { $0.order < $1.order }
                .map(\.key)
            let current = match.matches
                .filter { $0.candidate.side == side }
                .sorted { $0.candidate.order < $1.candidate.order }
                .map { $0.placement.key }
            if desired != current { return false }
        }
        return true
    }

    private func finish(result: ProfileApplyResult) {
        lastResult = result
        lastMessage = result.summary
        isBusy = false
    }

    private func finishBusy(message: String) {
        lastResult = nil
        lastMessage = message
        isBusy = false
    }

    private func persist() {
        isPersisting = true
        defer { isPersisting = false }
        Preferences.menuBarProfiles = profiles
        Preferences.activeProfileID = activeProfileID
        Preferences.defaultProfileID = defaultProfileID
        Preferences.applyDefaultProfileAtLaunch = applyDefaultAtLaunch
    }

    private func normalizedName(_ rawName: String) -> String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ProfileApplyReason {
    case user
    case launch
}
