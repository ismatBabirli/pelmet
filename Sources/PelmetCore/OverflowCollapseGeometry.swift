import CoreGraphics

/// Collapse lengths for macOS 27's single-window menu bar.
///
/// macOS 27 no longer clamps an oversized status item. Once one item's length
/// reaches a per-display limit, the change is discarded and the bar is left as
/// it was, which is why the offscreen collapse displaces nothing there. Below
/// the limit the bar does not reflow around the item: it overflows from the
/// left, moving the leftmost items into the system's own « menu until the rest
/// fits. So a collapse keeps the divider and each spacer under the narrowest
/// display's limit, while together they still span the widest display's
/// status area (one length applies to every display's copy of the bar).
///
/// Limits, measured on 27.0 by MenubarHide (MIT) and confirmed on 27.2 by a
/// Pelmet probe: half the width on a display without a notch; on a notched
/// display about 0.79 of the area right of the notch (a 1512 pt MacBook Pro
/// with 663.5 pt there takes 515 pt and discards 535 pt).
public enum OverflowCollapseGeometry {

    public struct Display: Equatable {
        /// Full width of the display.
        public let width: CGFloat
        /// Width available to status items: the area right of the notch when
        /// there is one, the full width otherwise.
        public let statusWidth: CGFloat

        public init(width: CGFloat, statusWidth: CGFloat? = nil) {
            self.width = width
            self.statusWidth = min(statusWidth ?? width, width)
        }

        var hasNotch: Bool { statusWidth < width }
    }

    public struct Plan: Equatable {
        /// Length for the divider and for every active spacer.
        public let unitLength: CGFloat
        /// How many spacers to inflate alongside the divider.
        public let activeSpacers: Int
    }

    /// Fixed, so every launch registers the same autosave names: a name first
    /// seen on a later launch lands leftmost, outside the divider's block. So
    /// it has to cover the widest setup up front. Sixteen spans a 6016 pt Pro
    /// Display XDR beside a MacBook Air scaled to 1280 pt (a 356 pt unit), the
    /// smallest unit and the widest status area Pelmet expects together.
    /// Uninflated spacers stay hidden and take no room.
    public static let spacerCount = 16

    /// Distance kept under a limit. It absorbs the measurements' imprecision
    /// and the 16 pt of chrome AppKit adds around each item's length.
    static let limitMargin: CGFloat = 64
    /// 0.75 of the area right of the notch stays under the measured ~0.79.
    static let notchedLimitFactor: CGFloat = 0.75
    static let fallbackUnit: CGFloat = 200

    /// The longest length one item can take on this display before macOS
    /// discards it.
    public static func limit(of display: Display) -> CGFloat {
        display.hasNotch
            ? display.statusWidth * notchedLimitFactor
            : display.width / 2
    }

    public static func plan(displays: [Display]) -> Plan {
        guard let lowestLimit = displays.map(limit(of:)).min(),
              let widestStatus = displays.map(\.statusWidth).max()
        else { return Plan(unitLength: fallbackUnit, activeSpacers: 0) }

        let unit = max(1, (lowestLimit - limitMargin).rounded(.down))
        // The divider is one unit; each spacer adds another. Spacers past the
        // widest status area would only overflow themselves, so use no more
        // than it takes to cover it.
        let needed = Int((widestStatus / unit).rounded(.up)) - 1
        return Plan(unitLength: unit, activeSpacers: min(max(needed, 0), spacerCount))
    }
}
