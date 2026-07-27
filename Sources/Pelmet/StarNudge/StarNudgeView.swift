import SwiftUI

/// The star-on-GitHub nudge card. Styled like the What's New window and the
/// onboarding tips: app icon, a short honest ask, and three actions. The star
/// button opens the repository in the user's browser (no in-app network call).
struct StarNudgeView: View {

    let onStar: () -> Void
    let onLater: () -> Void
    let onDontAsk: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)

            Text("Enjoying Pelmet?")
                .font(.title3.bold())

            Text("Pelmet is free and open source. If it has earned a spot in your "
                + "menu bar, a star on GitHub helps other people find it. It takes "
                + "a second and means a lot.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button(action: onStar) {
                    Text("Star on GitHub")
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
