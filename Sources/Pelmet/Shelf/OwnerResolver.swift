import AppKit
import PelmetCore

/// Resolves window-owner PIDs to app metadata and icons via
/// NSRunningApplication — permission-free. The Shelf and the activation
/// engine both lean on this.
final class OwnerResolver {

    static let shared = OwnerResolver()

    private var iconCache: [Int32: NSImage] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                self?.iconCache.removeAll()
                return
            }
            self?.iconCache.removeValue(forKey: app.processIdentifier)
        }
    }

    func info(for pid: Int32) -> RunningAppInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return RunningAppInfo(
            pid: pid,
            bundleID: app.bundleIdentifier,
            localizedName: app.localizedName
        )
    }

    func resolve(pids: Set<Int32>) -> [Int32: RunningAppInfo] {
        var result: [Int32: RunningAppInfo] = [:]
        for pid in pids {
            if let info = info(for: pid) { result[pid] = info }
        }
        return result
    }

    /// Control Center's PID — on macOS 26 (Tahoe) it owns every status-item
    /// window, which is exactly why its PID must never count as identity.
    func controlCenterPID() -> Int32? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
            .first?.processIdentifier
    }

    func icon(forPID pid: Int32) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        iconCache[pid] = icon
        return icon
    }

    /// Tier-0 fallback "activation": bring the owning app forward. Not the
    /// item's menu — that needs the engine — but proof of life the user can
    /// act on.
    func activateApp(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }
}
