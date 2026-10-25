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

    private let gridColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
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
            // Header Bar with Centered Title & Native macOS Back Navigation
            headerBar

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // GENERAL PREFERENCES SECTION
                    generalSection

                    // STORAGE & RETENTION SECTION
                    storageSection

                    // DANGER ZONE SECTION
                    dangerZoneSection
                }
                .padding(14)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        ZStack {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        viewModel.showingSettings = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.14))
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GENERAL")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.leading, 2)

            VStack(spacing: 0) {
                // 1. Start at Login Row
                HStack(spacing: 11) {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .frame(width: 26, height: 26)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start at Login")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Launch ClipBar automatically when your Mac turns on.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $startAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: startAtLogin) { newValue in
                            LaunchAtLoginHelper.setEnabled(newValue)
                        }
                }
                .padding(.vertical, 8)

                Divider().opacity(0.15).padding(.leading, 37)

                // 2. Pause Clipboard Recording Row
                HStack(spacing: 11) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                        .frame(width: 26, height: 26)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause Clipboard Recording")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Temporarily stop recording new clips into history.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $isPaused)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: isPaused) { newValue in
                            var updated = viewModel.settings
                            updated.isPaused = newValue
                            viewModel.updateSettings(updated)
                        }
                }
                .padding(.vertical, 8)

                Divider().opacity(0.15).padding(.leading, 37)

                // 3. Ignore Password Managers Row
                HStack(spacing: 11) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)
                        .frame(width: 26, height: 26)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ignore Password Managers")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Exclude 1Password, Bitwarden, Keychain, and concealed items.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $ignoreConcealed)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: ignoreConcealed) { newValue in
                            var updated = viewModel.settings
                            updated.ignoreConcealed = newValue
                            viewModel.updateSettings(updated)
                        }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Storage & Retention Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STORAGE & RETENTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.leading, 2)

            // Database Info Box
            databaseCard

            // Auto-Delete Presets
            autoDeleteCard

            // Keep At Most Presets
            keepAtMostCard

            // Scheduled Cleanup Info Banner
            cleanupNoticeBanner
        }
        .padding(13)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Subcomponents: Database Card

    private var databaseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row: Label & Size Badge
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary.opacity(0.9))
                    Text("DATABASE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.9))
                }

                Spacer()

                if let stats = viewModel.databaseStats {
                    HStack(spacing: 4.5) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                        Text(stats.formattedFileSize)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.14))
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
                    )
                }
            }

            // Path Row
            if let path = viewModel.dbPath {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
            }

            // Uniform Action Buttons Bar (Equal flexible widths)
            HStack(spacing: 7) {
                // Button 1: Reveal in Finder
                Button(action: {
                    if let path = viewModel.dbPath {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 10.5))
                        Text("Reveal in Finder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 27)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Show database in Finder")

                // Button 2: Copy Path
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
                    HStack(spacing: 5) {
                        Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5))
                        Text(copiedPath ? "Copied" : "Copy Path")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 27)
                    .background(copiedPath ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.07))
                    .foregroundColor(copiedPath ? .accentColor : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(copiedPath ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Copy full path to clipboard")

                // Button 3: Optimize / Vacuum
                Button(action: { viewModel.optimizeStorage() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5))
                        Text("Optimize")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 27)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Reclaim disk space and checkpoint SQLite WAL")
            }
            .padding(.top, 2)
        }
        .padding(11)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - Subcomponents: Auto-Delete Card

    private var autoDeleteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUTO-DELETE CLIPS NOT USED FOR")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))

            // Balanced 3-column grid for the 6 standard presets
            LazyVGrid(columns: gridColumns, spacing: 6) {
                ForEach(standardRetentionOptions, id: \.days) { option in
                    let isSelected = !isCustomRetention && retentionDays == option.days
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCustomRetention = false
                            retentionDays = option.days
                        }
                        var updated = viewModel.settings
                        updated.retentionDays = option.days
                        viewModel.updateSettings(updated)
                    }) {
                        Text(option.label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 27)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.1), lineWidth: 0.6)
                                    )
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Symmetrical Custom Days Bar
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCustomRetention.toggle()
                        if isCustomRetention {
                            retentionDays = customRetentionDays
                            var updated = viewModel.settings
                            updated.retentionDays = customRetentionDays
                            viewModel.updateSettings(updated)
                        } else {
                            retentionDays = 30
                            var updated = viewModel.settings
                            updated.retentionDays = 30
                            viewModel.updateSettings(updated)
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                        Text(isCustomRetention ? "Custom Retention" : "Custom Duration...")
                            .font(.system(size: 11, weight: isCustomRetention ? .semibold : .medium))
                    }
                    .foregroundColor(isCustomRetention ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if isCustomRetention {
                    HStack(spacing: 6) {
                        Text("\(customRetentionDays) days")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)

                        Stepper("", value: $customRetentionDays, in: 1...730)
                            .labelsHidden()
                            .controlSize(.small)
                            .onChange(of: customRetentionDays) { newValue in
                                retentionDays = newValue
                                var updated = viewModel.settings
                                updated.retentionDays = newValue
                                viewModel.updateSettings(updated)
                            }
                    }
                } else {
                    Text("e.g. 35 days")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isCustomRetention ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isCustomRetention ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Subcomponents: Keep At Most Card

    private var keepAtMostCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEEP AT MOST")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))

            // Balanced 3-column grid for the 6 standard presets
            LazyVGrid(columns: gridColumns, spacing: 6) {
                ForEach(standardHistoryOptions, id: \.count) { option in
                    let isSelected = !isCustomHistory && maxHistory == option.count
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCustomHistory = false
                            maxHistory = option.count
                        }
                        var updated = viewModel.settings
                        updated.maxHistory = option.count
                        viewModel.updateSettings(updated)
                    }) {
                        Text(option.label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 27)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.1), lineWidth: 0.6)
                                    )
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Symmetrical Custom Capacity Bar
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCustomHistory.toggle()
                        if isCustomHistory {
                            maxHistory = customHistoryLimit
                            var updated = viewModel.settings
                            updated.maxHistory = customHistoryLimit
                            viewModel.updateSettings(updated)
                        } else {
                            maxHistory = 1000
                            var updated = viewModel.settings
                            updated.maxHistory = 1000
                            viewModel.updateSettings(updated)
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "number")
                            .font(.system(size: 11))
                        Text(isCustomHistory ? "Custom Capacity" : "Custom Limit...")
                            .font(.system(size: 11, weight: isCustomHistory ? .semibold : .medium))
                    }
                    .foregroundColor(isCustomHistory ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if isCustomHistory {
                    HStack(spacing: 6) {
                        Text("\(customHistoryLimit) clips")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)

                        Stepper("", value: $customHistoryLimit, in: 50...50000, step: 250)
                            .labelsHidden()
                            .controlSize(.small)
                            .onChange(of: customHistoryLimit) { newValue in
                                maxHistory = newValue
                                var updated = viewModel.settings
                                updated.maxHistory = newValue
                                viewModel.updateSettings(updated)
                            }
                    }
                } else {
                    Text("e.g. 2,500 clips")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isCustomHistory ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isCustomHistory ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Subcomponents: Cleanup Notice Banner

    private var cleanupNoticeBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor.opacity(0.9))
                .padding(.top, 1)

            Text("Cleanup runs at startup, after each copy, and every 30 minutes. Pinned clips are never deleted automatically.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.9))
                Text("DANGER ZONE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.red.opacity(0.9))
            }
            .padding(.leading, 2)

            VStack(spacing: 0) {
                // 1. Clear Unpinned History
                if showingClearUnpinnedConfirmation {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Clear unpinned clips? Pinned clips will be kept safe.")
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
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))

                            Button("Confirm Clear") {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    viewModel.clearUnpinned()
                                    showingClearUnpinnedConfirmation = false
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.22))
                            .foregroundColor(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(9)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.vertical, 4)
                } else {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            showingClearUnpinnedConfirmation = true
                            showingDeleteAllConfirmation = false
                        }
                    }) {
                        HStack(spacing: 9) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                                .frame(width: 20)
                            Text("Clear Unpinned History")
                                .foregroundColor(.orange)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().opacity(0.15)

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
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))

                            Button("Delete Everything") {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    viewModel.deleteAllClips()
                                    showingDeleteAllConfirmation = false
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                        }
                    }
                    .padding(9)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.vertical, 4)
                } else {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            showingDeleteAllConfirmation = true
                            showingClearUnpinnedConfirmation = false
                        }
                    }) {
                        HStack(spacing: 9) {
                            Image(systemName: "xmark.bin")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .frame(width: 20)
                            Text("Delete All Clips (Fresh Start)")
                                .foregroundColor(.red)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().opacity(0.15)

                // 3. Quit ClipSuite
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 9) {
                        Image(systemName: "power")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text("Quit ClipSuite")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}
