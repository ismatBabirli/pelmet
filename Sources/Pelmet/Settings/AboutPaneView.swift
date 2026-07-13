import SwiftUI

/// About pane: the app's identity, its version (with a copy-for-bug-reports
/// button), the open-source links, and the license. A menu-bar-only app has no
/// app menu, so this pane is the stand-in for the "About Pelmet" item that
/// would normally live there.
struct AboutPaneView: View {

    private let version = AppVersionInfo.current
    @State private var didCopy = false

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

            Section {
                Link("View on GitHub", destination: AppLinks.repo)
                Link("Release Notes", destination: AppLinks.releases)
                Link("Report an Issue…", destination: AppLinks.issues)
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
