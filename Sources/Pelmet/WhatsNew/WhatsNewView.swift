import AppKit
import PelmetCore
import SwiftUI

struct WhatsNewView: View {
    let versionLabel: String
    let releases: [ChangelogRelease]
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.vertical, 22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if releases.isEmpty {
                        fallbackContent
                    } else {
                        if !hasCurrentRelease {
                            fallbackContent
                        }
                        ForEach(Array(releases.enumerated()), id: \.offset) { _, release in
                            releaseView(release)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            .textSelection(.enabled)

            Divider()

            HStack {
                Link("View Full Changelog", destination: AppLinks.changelog)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("What's New in Pelmet \(versionLabel)")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(releases.count > 1
                    ? "Here’s everything that changed across the updates you skipped."
                    : "Pelmet has been updated. Here are the highlights.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fallbackContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pelmet was updated to version \(versionLabel).")
                .font(.headline)
            Text("The bundled notes for this version aren't available. You can still read the full changelog on GitHub.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hasCurrentRelease: Bool {
        releases.contains { $0.version.description == versionLabel }
    }

    private func releaseView(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Version \(release.version.description)")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if let date = release.date {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .accessibilityHidden(true)
                            Text(attributedMarkdown(item))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if release.sections.isEmpty {
                Text("The bundled notes for this version aren't available. See the full changelog on GitHub.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func attributedMarkdown(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}

#Preview("Current release") {
    WhatsNewView(
        versionLabel: "0.4.0",
        releases: [ChangelogRelease(
            version: SemanticVersion("0.4.0")!,
            date: "2026-08-01",
            sections: [
                ChangelogSection(
                    title: "Added",
                    items: ["A focused **What's New** window after updates."]
                ),
                ChangelogSection(title: "Fixed", items: ["Improved launch presentation ordering."]),
            ]
        )],
        onDone: {}
    )
    .frame(width: 560, height: 600)
}

#Preview("Skipped releases") {
    WhatsNewView(
        versionLabel: "0.4.0",
        releases: [
            ChangelogRelease(
                version: SemanticVersion("0.4.0")!,
                sections: [ChangelogSection(title: "Added", items: ["Current changes."])]
            ),
            ChangelogRelease(
                version: SemanticVersion("0.3.1")!,
                sections: [ChangelogSection(title: "Fixed", items: ["Earlier fixes."])]
            ),
        ],
        onDone: {}
    )
    .frame(width: 560, height: 600)
}

#Preview("Fallback") {
    WhatsNewView(versionLabel: "0.4.0", releases: [], onDone: {})
        .frame(width: 560, height: 600)
}
