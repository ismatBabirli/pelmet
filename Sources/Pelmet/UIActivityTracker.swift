import Foundation

/// Counts open Pelmet UI surfaces (tip popovers, Make Room window, Settings)
/// so auto-rehide never collapses the bar under an open explainer.
final class UIActivityTracker {

    static let shared = UIActivityTracker()

    private(set) var openSurfaces = 0

    /// Fired when the first surface opens (pause the rehide timer).
    var onFirstOpened: (() -> Void)?
    /// Fired when the last surface closes (restart the rehide timer fresh).
    var onAllClosed: (() -> Void)?

    func surfaceOpened() {
        openSurfaces += 1
        if openSurfaces == 1 { onFirstOpened?() }
    }

    func surfaceClosed() {
        guard openSurfaces > 0 else { return }
        openSurfaces -= 1
        if openSurfaces == 0 { onAllClosed?() }
    }
}
