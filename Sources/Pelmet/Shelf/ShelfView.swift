import SwiftUI
import PelmetCore

/// The Shelf's content: a frosted card listing the icons the notch hid.
/// Rows are real buttons (VoiceOver reads them for free); keyboard events
/// arrive from the panel via the view model, not SwiftUI focus.
struct ShelfView: View {

    @ObservedObject var model: ShelfViewModel

    /// Must stay above 300 — see the classifier note in ShelfPanel.
    static let panelWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.rows.isEmpty {
                header
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }

            if model.rows.isEmpty {
                emptyState
                    .padding(.top, 12)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isSelected: model.selectedIndex == index)
                        if model.expandedExplanationID == row.id {
                            explanationCallout(for: row)
                        }
                        if let failure = model.inlineFailure, failure.rowID == row.id {
                            failureCallout(failure.message)
                        }
                    }
                }
                .padding(.horizontal, 6)
            }

            if !model.rows.isEmpty {
                footer
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: Self.panelWidth)
        .background(ShelfBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pelmet Shelf: icons hidden by the notch")
    }

    // MARK: - Sections

    private var header: some View {
        Text(headerText)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerText: String {
        switch model.tier {
        case .owners, .engine:
            return "Hidden by the notch"
        case .anonymous:
            return "Hidden by the notch. macOS 26 hides which apps these belong to"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Everything fits. Nothing is hidden by the notch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func rowView(_ row: ShelfRow, isSelected: Bool) -> some View {
        Button {
            model.activate(row)
        } label: {
            HStack(spacing: 10) {
                rowIcon(row)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rowTitle(row))
                        .font(.body)
                        .lineLimit(1)
                    if let subtitle = rowSubtitle(row) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowTitle(row))
        .accessibilityHint(rowAccessibilityHint(row))
    }

    @ViewBuilder
    private func rowIcon(_ row: ShelfRow) -> some View {
        if let icon = row.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private func rowTitle(_ row: ShelfRow) -> String {
        switch row.model.kind {
        case .app(_, let name, _): return name
        case .engineItem(_, let title, _): return title
        case .unknown(let ordinal): return "Hidden item \(ordinal)"
        }
    }

    private func rowSubtitle(_ row: ShelfRow) -> String? {
        if case .app(_, _, let count) = row.model.kind, count > 1 {
            return "\(count) items"
        }
        return nil
    }

    private func rowAccessibilityHint(_ row: ShelfRow) -> String {
        switch row.model.kind {
        case .engineItem:
            return "Opens this menu bar item."
        case .app:
            return "Brings the app forward. Enable one-click access to open the menu bar item directly."
        case .unknown:
            return "Shows what Pelmet can do about this hidden item."
        }
    }

    @ViewBuilder
    private func explanationCallout(for row: ShelfRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(explanationText(for: row))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.canOfferEngineOptIn {
                Button(model.optInIsBlocked ? "Open System Settings…" : "Enable one-click access…") {
                    model.offerOptIn()
                }
                .font(.caption)
                if model.optInIsBlocked {
                    Text("Pelmet is waiting for the Accessibility permission.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func explanationText(for row: ShelfRow) -> String {
        switch row.model.kind {
        case .app(_, let name, _):
            return "macOS won't let Pelmet open \(name)'s menu without the Accessibility permission. One-click access is opt-in and never reads your screen."
        default:
            return "Enable one-click access to identify these items and open them with a single click. It uses the Accessibility permission and never reads your screen."
        }
    }

    private func failureCallout(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.yellow.opacity(0.12))
            )
    }

    private var footer: some View {
        HStack {
            Button("Make Room…") {
                MakeRoomWindowController.shared.show()
                model.onRequestClose?()
            }
            .font(.caption)
            Spacer()
            if model.canOfferEngineOptIn, !model.rows.isEmpty {
                Button(model.optInIsBlocked ? "Open System Settings…" : "Enable one-click access…") {
                    model.offerOptIn()
                }
                .font(.caption)
            }
        }
        .buttonStyle(.link)
    }
}

/// Frosted background. NSVisualEffectView natively honors Reduce
/// Transparency (draws opaque), so no extra handling is needed.
private struct ShelfBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
