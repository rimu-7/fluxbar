import SwiftUI
import AppKit
import ClipCore

/// The "Software Update" window: new version, release notes and install progress.
struct UpdateAlertView: View {
    @ObservedObject var updater: GitHubUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            Divider()
            footer
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 460)
        .frame(minHeight: 200)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch updater.state {
        case .idle, .checking: return "Checking for Updates…"
        case .upToDate: return "FluxBar is up to date"
        case .available(let update), .downloading(let update, _):
            return "FluxBar \(update.version) is available"
        case .readyToInstall(let update, _): return "FluxBar \(update.version) is ready to install"
        case .installing: return "Installing…"
        case .error: return "Update failed"
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .idle, .checking: return "Contacting GitHub."
        case .upToDate: return "You have the latest version, \(updater.currentVersion)."
        case .available(let update), .downloading(let update, _):
            return "You have \(update.currentVersion). Your clipboard history and settings are kept."
        case .readyToInstall: return "FluxBar will quit, update and reopen. This takes a few seconds."
        case .installing: return "FluxBar will reopen in a moment."
        case .error(let message): return message
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking, .installing:
            ProgressView()
                .progressViewStyle(.linear)

        case .available(let update):
            ReleaseNotesView(notes: update.notes)
            if let blocker = updater.installBlocker {
                Label(blocker, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

        case .downloading(let update, let progress):
            ReleaseNotesView(notes: update.notes)
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(progress < 1 ? "Downloading… \(Int(progress * 100))%" : "Verifying…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

        case .readyToInstall(let update, _):
            ReleaseNotesView(notes: update.notes)

        case .upToDate, .error:
            EmptyView()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Check automatically", isOn: $updater.automaticallyChecks)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            switch updater.state {
            case .available(let update):
                Button("Skip This Version") { updater.skip(update) }
                Button("Later") { updater.dismiss() }
                if updater.installBlocker == nil {
                    Button("Download and Install") { updater.downloadAndInstall() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open Release Page") { updater.openReleasePage() }
                        .keyboardShortcut(.defaultAction)
                }

            case .downloading:
                Button("Cancel") { updater.cancelDownload() }
                    .keyboardShortcut(.cancelAction)

            case .readyToInstall:
                Button("Later") { updater.dismiss() }
                Button("Install and Relaunch") { updater.installAndRelaunch() }
                    .keyboardShortcut(.defaultAction)

            case .error:
                Button("Open Release Page") { updater.openReleasePage() }
                Button("Try Again") { updater.checkForUpdates(userInitiated: true) }
                    .keyboardShortcut(.defaultAction)

            case .upToDate:
                Button("OK") { updater.dismiss() }
                    .keyboardShortcut(.defaultAction)

            case .idle, .checking, .installing:
                EmptyView()
            }
        }
        .controlSize(.regular)
    }
}

/// Renders GitHub release notes: headings, bullet lists and inline Markdown (bold, links, code).
private struct ReleaseNotesView: View {
    let notes: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                if notes.isEmpty {
                    Text("No release notes.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        row(for: line)
                    }
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .textSelection(.enabled)
        }
        .frame(height: 190)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var lines: [String] {
        notes.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("<!--") }
    }

    @ViewBuilder
    private func row(for line: String) -> some View {
        if line.hasPrefix("#") {
            Text(inline(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.top, 4)
        } else if line.hasPrefix("* ") || line.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundColor(.secondary)
                Text(inline(String(line.dropFirst(2))))
            }
        } else {
            Text(inline(line))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
