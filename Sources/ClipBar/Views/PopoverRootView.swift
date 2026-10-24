import SwiftUI
import ClipCore

public struct PopoverRootView: View {
    @StateObject private var viewModel = ClipBarViewModel()
    @FocusState private var isSearchFocused: Bool

    public init() {}

    public var body: some View {
        ZStack {
            if viewModel.showingSettings {
                SettingsView(viewModel: viewModel)
                    .transition(.move(edge: .trailing))
            } else {
                mainContentView
                    .transition(.move(edge: .leading))
            }
        }
        .frame(width: 380, height: 480)
        .background(.ultraThinMaterial)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header Bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Search Field
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        TextField("Search clips (FTS5)...", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .focused($isSearchFocused)

                        if !viewModel.searchQuery.isEmpty {
                            Button(action: { viewModel.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(7)

                    // Pause / Resume Badge Button
                    Button(action: { viewModel.togglePause() }) {
                        Image(systemName: viewModel.settings.isPaused ? "pause.circle.fill" : "record.circle")
                            .font(.system(size: 14))
                            .foregroundColor(viewModel.settings.isPaused ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.settings.isPaused ? "Recording paused. Click to resume." : "Recording active. Click to pause.")

                    // Settings Button
                    Button(action: { viewModel.showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                }

                // Filter Bar & Clip Count
                HStack {
                    Picker("Filter", selection: $viewModel.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)

                    Spacer()

                    if viewModel.settings.isPaused {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text("PAUSED")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    } else {
                        Text("\(viewModel.clips.count) items")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // List of Clips or Empty State
            if viewModel.clips.isEmpty {
                emptyStateView
            } else {
                clipsListView
            }

            // Keyboard Shortcuts Footer
            keyboardHelpFooter
        }
    }

    private var clipsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            isSelected: viewModel.selectedIndex == index,
                            quickIndex: index < 9 ? (index + 1) : nil,
                            isCopied: viewModel.copiedClipId == item.id,
                            onSelect: {
                                viewModel.selectedIndex = index
                                viewModel.copyClip(item)
                            },
                            onCopy: {
                                viewModel.copyClip(item)
                            },
                            onTogglePin: {
                                viewModel.togglePin(item)
                            },
                            onDelete: {
                                viewModel.deleteClip(item)
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: viewModel.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))

            Text(viewModel.searchQuery.isEmpty ? "No Clips Saved" : "No Matching Clips")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Text(viewModel.searchQuery.isEmpty ? "Copy text anywhere to begin saving history." : "Try a different search query.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyboardHelpFooter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Text("↑↓").font(.system(size: 10, weight: .bold))
                Text("Navigate").font(.system(size: 9.5))
            }
            HStack(spacing: 2) {
                Text("↵").font(.system(size: 10, weight: .bold))
                Text("Copy").font(.system(size: 9.5))
            }
            HStack(spacing: 2) {
                Text("⌘P").font(.system(size: 10, weight: .bold))
                Text("Pin").font(.system(size: 9.5))
            }
            HStack(spacing: 2) {
                Text("⌫").font(.system(size: 10, weight: .bold))
                Text("Delete").font(.system(size: 9.5))
            }
            HStack(spacing: 2) {
                Text("⌘1-9").font(.system(size: 10, weight: .bold))
                Text("Quick").font(.system(size: 9.5))
            }
            Spacer()
        }
        .foregroundColor(.secondary.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        // Keyboard Shortcuts handling
        .background(
            KeyboardShortcutsHandler(viewModel: viewModel)
        )
    }
}

// Background invisible keyboard shortcut receptor
private struct KeyboardShortcutsHandler: View {
    @ObservedObject var viewModel: ClipBarViewModel

    var body: some View {
        ZStack {
            // Up Arrow
            Button("") {
                viewModel.selectPrevious()
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            // Down Arrow
            Button("") {
                viewModel.selectNext()
            }
            .keyboardShortcut(.downArrow, modifiers: [])

            // Return to copy
            Button("") {
                viewModel.copySelected()
            }
            .keyboardShortcut(.return, modifiers: [])

            // Cmd + P to Pin
            Button("") {
                viewModel.togglePinSelected()
            }
            .keyboardShortcut("p", modifiers: .command)

            // Delete to remove
            Button("") {
                viewModel.deleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])

            // 1 to 9 Quick copy
            ForEach(1...9, id: \.self) { digit in
                Button("") {
                    viewModel.copyQuick(index: digit - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(48 + digit)!)), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
