import SwiftUI
import AppKit
import ClipCore

public struct SettingsView: View {
    @ObservedObject var viewModel: ClipBarViewModel

    @State private var startAtLogin: Bool = LaunchAtLoginHelper.isEnabled
    @State private var isPaused: Bool
    @State private var ignoreConcealed: Bool
    @State private var retentionDays: Int
    @State private var maxHistory: Int

    @State private var isCustomRetention: Bool = false
    @State private var customRetentionDays: Int = 35
    @State private var isCustomHistory: Bool = false
    @State private var customHistoryLimit: Int = 2500

    @State private var copiedPath: Bool = false
    @State private var showingClearUnpinnedConfirmation: Bool = false
    @State private var showingDeleteAllConfirmation: Bool = false

    private let standardRetentionOptions: [(label: String, days: Int)] = [
        ("1 day", 1),
        ("7 days", 7),
        ("30 days", 30),
        ("90 days", 90),
        ("1 year", 365),
        ("Never", 0)
    ]

    private let standardHistoryOptions: [(label: String, count: Int)] = [
        ("200", 200),
        ("500", 500),
        ("1,000", 1000),
        ("5,000", 5000),
        ("20,000", 20000),
        ("Unlimited", 0)
    ]

    public init(viewModel: ClipBarViewModel) {
        self.viewModel = viewModel
        let currentSettings = viewModel.settings
        _isPaused = State(initialValue: currentSettings.isPaused)
        _ignoreConcealed = State(initialValue: currentSettings.ignoreConcealed)
        _retentionDays = State(initialValue: currentSettings.retentionDays)
        _maxHistory = State(initialValue: currentSettings.maxHistory)

        let isStandardRetention = [1, 7, 30, 90, 365, 0].contains(currentSettings.retentionDays)
        _isCustomRetention = State(initialValue: !isStandardRetention)
        _customRetentionDays = State(initialValue: isStandardRetention ? 35 : currentSettings.retentionDays)

        let isStandardHistory = [200, 500, 1000, 5000, 20000, 0].contains(currentSettings.maxHistory)
        _isCustomHistory = State(initialValue: !isStandardHistory)
        _customHistoryLimit = State(initialValue: isStandardHistory ? 2500 : currentSettings.maxHistory)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Frosted Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.showingSettings = false
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5)
                            .fill(Color.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 6.5).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Color.clear.frame(width: 54, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.black.opacity(0.12))

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // General / Launch Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GENERAL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))

                        Toggle(isOn: $startAtLogin) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start at Login")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Launch ClipBar automatically when your Mac turns on.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .onChange(of: startAtLogin) { newValue in
                            LaunchAtLoginHelper.setEnabled(newValue)
                        }

                        Divider().opacity(0.2).padding(.vertical, 1)

                        Toggle(isOn: $isPaused) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pause Clipboard Recording")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Temporarily stop recording new clips into history.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .onChange(of: isPaused) { newValue in
                            var updated = viewModel.settings
                            updated.isPaused = newValue
                            viewModel.updateSettings(updated)
                        }

                        Divider().opacity(0.2).padding(.vertical, 1)

                        Toggle(isOn: $ignoreConcealed) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ignore Password Managers")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Exclude 1Password, Bitwarden, Keychain, and sensitive items.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .onChange(of: ignoreConcealed) { newValue in
                            var updated = viewModel.settings
                            updated.ignoreConcealed = newValue
                            viewModel.updateSettings(updated)
                        }
                    }
                    .padding(13)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            }
                    }

                    // Storage & Retention Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("STORAGE & RETENTION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))

                        // DATABASE Info Card
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("DATABASE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.8))
                                Spacer()
                                if let stats = viewModel.databaseStats {
                                    Text(stats.formattedFileSize)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                }
                            }

                            if let path = viewModel.dbPath {
                                Text(path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }

                            HStack(spacing: 8) {
                                Button(action: {
                                    if let path = viewModel.dbPath {
                                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 10.5))
                                        Text("Reveal in Finder")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(Color.white.opacity(0.07))
                                    .overlay(RoundedRectangle(cornerRadius: 5.5).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                                    .cornerRadius(5.5)
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    if let path = viewModel.dbPath {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(path, forType: .string)
                                        copiedPath = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            copiedPath = false
                                        }
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10.5))
                                        Text(copiedPath ? "Copied" : "Copy Path")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(copiedPath ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.07))
                                    .foregroundColor(copiedPath ? .accentColor : .primary)
                                    .overlay(RoundedRectangle(cornerRadius: 5.5).strokeBorder(copiedPath ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 0.5))
                                    .cornerRadius(5.5)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: { viewModel.optimizeStorage() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 10))
                                        Text("Optimize")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4.5)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(5.5)
                                }
                                .buttonStyle(.plain)
                                .help("Reclaim disk space and checkpoint SQLite WAL")
                            }
                            .padding(.top, 2)
                        }
                        .padding(11)
                        .background(Color.black.opacity(0.14))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))

                        // AUTO-DELETE CLIPS NOT USED FOR (Time-based Retention)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AUTO-DELETE CLIPS NOT USED FOR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.8))

                            // Grid of Presets
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 6)], spacing: 6) {
                                ForEach(standardRetentionOptions, id: \.days) { option in
                                    let isSelected = !isCustomRetention && retentionDays == option.days
                                    Button(action: {
                                        isCustomRetention = false
                                        retentionDays = option.days
                                        var updated = viewModel.settings
                                        updated.retentionDays = option.days
                                        viewModel.updateSettings(updated)
                                    }) {
                                        Text(option.label)
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background {
                                                RoundedRectangle(cornerRadius: 6.5)
                                                    .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.06))
                                                    .overlay {
                                                        RoundedRectangle(cornerRadius: 6.5)
                                                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 0.6)
                                                    }
                                            }
                                            .foregroundColor(isSelected ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Custom Button
                                Button(action: {
                                    isCustomRetention = true
                                    retentionDays = customRetentionDays
                                    var updated = viewModel.settings
                                    updated.retentionDays = customRetentionDays
                                    viewModel.updateSettings(updated)
                                }) {
                                    Text(isCustomRetention ? "\(customRetentionDays) (custom)" : "Custom")
                                        .font(.system(size: 11, weight: isCustomRetention ? .semibold : .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background {
                                            RoundedRectangle(cornerRadius: 6.5)
                                                .fill(isCustomRetention ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.06))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 6.5)
                                                        .strokeBorder(isCustomRetention ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 0.6)
                                                }
                                        }
                                        .foregroundColor(isCustomRetention ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }

                            // Custom Retention Stepper if active
                            if isCustomRetention {
                                HStack {
                                    Text("Custom Days:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Stepper("\(customRetentionDays) days", value: $customRetentionDays, in: 1...730)
                                        .font(.system(size: 11, design: .monospaced))
                                        .onChange(of: customRetentionDays) { newValue in
                                            retentionDays = newValue
                                            var updated = viewModel.settings
                                            updated.retentionDays = newValue
                                            viewModel.updateSettings(updated)
                                        }
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)
                            }
                        }

                        Divider().opacity(0.2).padding(.vertical, 1)

                        // KEEP AT MOST (Capacity Limit)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("KEEP AT MOST")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.8))

                            // Grid of Presets
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 6)], spacing: 6) {
                                ForEach(standardHistoryOptions, id: \.count) { option in
                                    let isSelected = !isCustomHistory && maxHistory == option.count
                                    Button(action: {
                                        isCustomHistory = false
                                        maxHistory = option.count
                                        var updated = viewModel.settings
                                        updated.maxHistory = option.count
                                        viewModel.updateSettings(updated)
                                    }) {
                                        Text(option.label)
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background {
                                                RoundedRectangle(cornerRadius: 6.5)
                                                    .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.06))
                                                    .overlay {
                                                        RoundedRectangle(cornerRadius: 6.5)
                                                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 0.6)
                                                    }
                                            }
                                            .foregroundColor(isSelected ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Custom Button
                                Button(action: {
                                    isCustomHistory = true
                                    maxHistory = customHistoryLimit
                                    var updated = viewModel.settings
                                    updated.maxHistory = customHistoryLimit
                                    viewModel.updateSettings(updated)
                                }) {
                                    Text(isCustomHistory ? "\(customHistoryLimit) (custom)" : "Custom")
                                        .font(.system(size: 11, weight: isCustomHistory ? .semibold : .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background {
                                            RoundedRectangle(cornerRadius: 6.5)
                                                .fill(isCustomHistory ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.06))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 6.5)
                                                        .strokeBorder(isCustomHistory ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 0.6)
                                                }
                                        }
                                        .foregroundColor(isCustomHistory ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }

                            // Custom History Stepper if active
                            if isCustomHistory {
                                HStack {
                                    Text("Custom Limit:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Stepper("\(customHistoryLimit) clips", value: $customHistoryLimit, in: 50...50000, step: 250)
                                        .font(.system(size: 11, design: .monospaced))
                                        .onChange(of: customHistoryLimit) { newValue in
                                            maxHistory = newValue
                                            var updated = viewModel.settings
                                            updated.maxHistory = newValue
                                            viewModel.updateSettings(updated)
                                        }
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)
                            }
                        }

                        // Cleanup Schedule Information Notice
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor.opacity(0.9))
                                .padding(.top, 1)

                            Text("Cleanup runs at startup, after each copy, and every 30 minutes. Pinned clips are never deleted automatically.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(7)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5))
                    }
                    .padding(13)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            }
                    }

                    // Danger Zone Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DANGER ZONE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red.opacity(0.85))

                        // 1. Clear Unpinned History
                        if showingClearUnpinnedConfirmation {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Clear unpinned clips? Pinned clips will be kept.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    Button("Cancel") {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            showingClearUnpinnedConfirmation = false
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(5)

                                    Button("Confirm Clear") {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            viewModel.clearUnpinned()
                                            showingClearUnpinnedConfirmation = false
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5))
                                    .cornerRadius(5)
                                }
                            }
                            .padding(9)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(7)
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    showingClearUnpinnedConfirmation = true
                                    showingDeleteAllConfirmation = false
                                }
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .foregroundColor(.orange)
                                    Text("Clear Unpinned History")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().opacity(0.2).padding(.vertical, 2)

                        // 2. Delete All Clips (Fresh Start)
                        if showingDeleteAllConfirmation {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("⚠️ Delete ALL clips including pinned items?")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.red)
                                HStack(spacing: 8) {
                                    Button("Cancel") {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            showingDeleteAllConfirmation = false
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(5)

                                    Button("Delete Everything") {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            viewModel.deleteAllClips()
                                            showingDeleteAllConfirmation = false
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                                }
                            }
                            .padding(9)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(7)
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    showingDeleteAllConfirmation = true
                                    showingClearUnpinnedConfirmation = false
                                }
                            }) {
                                HStack {
                                    Image(systemName: "xmark.bin")
                                        .foregroundColor(.red)
                                    Text("Delete All Clips (Fresh Start)")
                                        .foregroundColor(.red)
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().opacity(0.2).padding(.vertical, 2)

                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            HStack {
                                Image(systemName: "power")
                                    .foregroundColor(.secondary)
                                Text("Quit ClipSuite")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(13)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            }
                    }
                }
                .padding(12)
            }
        }
    }
}
