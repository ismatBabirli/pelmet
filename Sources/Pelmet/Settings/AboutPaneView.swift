import SwiftUI

/// About pane: the app's identity, its version (with a copy-for-bug-reports
/// button), the open-source links, and the license. A menu-bar-only app has no
/// app menu, so this pane is the stand-in for the "About Pelmet" item that
/// would normally live there.
struct AboutPaneView: View {

    private let version = AppVersionInfo.current
    @State private var didCopy = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    // The real AppIcon in the bundled `.app`; the generic app
                    // icon under `swift run` (no bundle icon); honest, never a
                    // crash.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("Pelmet")
                        .font(.title3.bold())
                    Text("Menu-bar manager for macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Version") {
                    HStack(spacing: 6) {
                        Text(version.displayValue)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button(action: copyVersion) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy version for bug reports")
                    }
                }
            }

            // Uniform, System-Settings-style rows: a tinted glyph, a title, and
            // a trailing hint (an up-right arrow leaves for the browser, a
            // chevron opens an in-app window). One GitHub link, not two.
            Section {
                AboutRow(
                    title: "Star on GitHub",
                    subtitle: "It is free and open source. A star helps others find it.",
                    systemImage: "star.fill",
                    tint: .yellow,
                    opensExternally: true
                ) { openURL(AppLinks.repo) }

                AboutRow(title: "What's New", systemImage: "sparkles", tint: .accentColor) {
                    WhatsNewWindowController.shared.showManually()
                }

                AboutRow(
                    title: "Full Changelog",
                    systemImage: "doc.plaintext",
                    tint: .secondary,
                    opensExternally: true
                ) { openURL(AppLinks.changelog) }

                // Opens a GitHub issue prefilled with the version and
                // environment; the user writes and submits it themselves.
                AboutRow(title: "Report a Problem", systemImage: "ladybug", tint: .orange) {
                    CrashReportMonitor.shared.reportProblem()
                }
            } footer: {
                Text("\(AppVersionInfo.copyright) · Open source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func copyVersion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(version.labeled(), forType: .string)
        didCopy = true
    }
}

/// A single tappable About-pane row: leading tinted glyph, title (with an
/// optional one-line subtitle), and a trailing affordance that distinguishes an
/// external link from an in-app action. The whole row is the hit target.
private struct AboutRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var tint: Color = .accentColor
    var opensExternally = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: opensExternally ? "arrow.up.forward" : "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
