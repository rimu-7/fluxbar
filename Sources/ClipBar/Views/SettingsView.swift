import SwiftUI
import ClipCore

public struct SettingsView: View {
    @ObservedObject var viewModel: ClipBarViewModel
    @State private var maxHistory: Int
    @State private var isPaused: Bool
    @State private var ignoreConcealed: Bool
    @State private var showingClearUnpinnedConfirmation: Bool = false
    @State private var showingDeleteAllConfirmation: Bool = false

    public init(viewModel: ClipBarViewModel) {
        self.viewModel = viewModel
        _maxHistory = State(initialValue: viewModel.settings.maxHistory)
        _isPaused = State(initialValue: viewModel.settings.isPaused)
        _ignoreConcealed = State(initialValue: viewModel.settings.ignoreConcealed)
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

                // Balance spacer
                Color.clear.frame(width: 54, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.black.opacity(0.12))

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Recording Section Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECORDING & PRIVACY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))

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

                        Divider().opacity(0.2).padding(.vertical, 2)

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
                    .padding(13)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            }
                    }

                    // History Limit Section Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("STORAGE & HISTORY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))

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

                        Divider().opacity(0.2).padding(.vertical, 2)

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

                            Divider().opacity(0.2).padding(.vertical, 2)

                            Button(action: { viewModel.optimizeStorage() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                    Text("Reclaim Storage & Truncate WAL")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
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

                    // Data Management Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DATA MANAGEMENT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))

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
