import SwiftUI
import ClipCore

public struct SettingsView: View {
    @ObservedObject var viewModel: ClipBarViewModel
    @State private var maxHistory: Int
    @State private var isPaused: Bool
    @State private var ignoreConcealed: Bool
    @State private var showingClearConfirmation: Bool = false

    public init(viewModel: ClipBarViewModel) {
        self.viewModel = viewModel
        _maxHistory = State(initialValue: viewModel.settings.maxHistory)
        _isPaused = State(initialValue: viewModel.settings.isPaused)
        _ignoreConcealed = State(initialValue: viewModel.settings.ignoreConcealed)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { viewModel.showingSettings = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                // Balance spacer
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.04))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Recording Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECORDING & PRIVACY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Toggle(isOn: $isPaused) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pause Clipboard Recording")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Stop saving new clipboard items into history.")
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

                        Divider().padding(.vertical, 2)

                        Toggle(isOn: $ignoreConcealed) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ignore Password Managers")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Exclude 1Password, Bitwarden, Keychain, and concealed items.")
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
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // History Limit Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("STORAGE & HISTORY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Maximum Unpinned Clips")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Older items are automatically pruned by SQLite.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Stepper("\(maxHistory)", value: $maxHistory, in: 50...2000, step: 50)
                                .onChange(of: maxHistory) { newValue in
                                    var updated = viewModel.settings
                                    updated.maxHistory = newValue
                                    viewModel.updateSettings(updated)
                                }
                        }

                        Divider().padding(.vertical, 2)

                        // Live DB Stats
                        if let stats = viewModel.databaseStats {
                            HStack {
                                Label("Total Clips", systemImage: "doc.on.clipboard")
                                    .font(.system(size: 11.5))
                                Spacer()
                                Text("\(stats.totalClips) (\(stats.pinnedClips) pinned)")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Label("Database Size", systemImage: "cylinder.split.1x2")
                                    .font(.system(size: 11.5))
                                Spacer()
                                Text(stats.formattedFileSize)
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // Danger Zone / Maintenance
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DATA MANAGEMENT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Button(action: { showingClearConfirmation = true }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Clear Unpinned History")
                                    .foregroundColor(.red)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog(
                            "Clear Unpinned History?",
                            isPresented: $showingClearConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Clear All Unpinned Clips", role: .destructive) {
                                viewModel.clearUnpinned()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will permanently remove all non-pinned clips from SQLite. Pinned clips will not be deleted.")
                        }

                        Divider().padding(.vertical, 2)

                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            HStack {
                                Image(systemName: "power")
                                    .foregroundColor(.secondary)
                                Text("Quit ClipSuite")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
                .padding(14)
            }
        }
    }
}
