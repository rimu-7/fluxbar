import SwiftUI
import AppKit
import ClipCore

public struct PopoverRootView: View {
    @ObservedObject public var viewModel: ClipBarViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var keyMonitor: Any?

    public init(viewModel: ClipBarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            if viewModel.showingSettings {
                SettingsView(viewModel: viewModel)
            } else {
                mainContentView
            }
        }
        .frame(width: 380, height: 500)
        .background(.ultraThinMaterial)
        .onAppear {
            isSearchFocused = true
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
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
                            .onSubmit {
                                viewModel.copySelected()
                            }

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
                    Picker("", selection: $viewModel.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
                LazyVStack(spacing: 3) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("⌘⌫").font(.system(size: 10, weight: .bold))
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
    }

    // MARK: - Native Keyboard Monitor

    private func setupKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
            guard let vm = viewModel else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommand = flags.contains(.command)

            // 1. Arrow Down
            if event.keyCode == 125 {
                vm.selectNext()
                return nil
            }

            // 2. Arrow Up
            if event.keyCode == 126 {
                vm.selectPrevious()
                return nil
            }

            // 3. Cmd + P: Pin / Unpin
            if isCommand && (event.charactersIgnoringModifiers?.lowercased() == "p") {
                vm.togglePinSelected()
                return nil
            }

            // 4. Return: Copy selected
            if event.keyCode == 36 && flags.isEmpty {
                vm.copySelected()
                return nil
            }

            // 5. Cmd + Delete / Cmd + Backspace: ONLY delete when Cmd modifier is explicitly held
            // Plain backspace will NEVER delete clips!
            if isCommand && (event.keyCode == 51 || event.keyCode == 117) {
                vm.deleteSelected()
                return nil
            }

            // 6. Cmd + 1...9: Quick copy
            if isCommand, let char = event.charactersIgnoringModifiers?.first, let digit = char.wholeNumberValue, digit >= 1 && digit <= 9 {
                vm.copyQuick(index: digit - 1)
                return nil
            }

            // 7. Escape: Clear search
            if event.keyCode == 53 {
                if !vm.searchQuery.isEmpty {
                    vm.searchQuery = ""
                    return nil
                }
            }

            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
