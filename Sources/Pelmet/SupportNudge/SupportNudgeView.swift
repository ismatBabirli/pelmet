import SwiftUI

/// The support nudge card. It keeps the same lightweight, dismissible shape as
/// the star prompt while making the financial ask explicit and optional.
struct SupportNudgeView: View {

    let onSupport: () -> Void
    let onLater: () -> Void
    let onDontAsk: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)

            Text("Keep Pelmet free")
                .font(.title3.bold())

            Text("Pelmet is free and open source. If it helps keep your menu bar tidy, "
                + "a one-time or monthly contribution helps fund maintenance, macOS "
                + "compatibility work, and new features.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button(action: onSupport) {
                    Text("Support Pelmet")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)

                Button("Maybe Later", action: onLater)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Button("Don't ask again", action: onDontAsk)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
