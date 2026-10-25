import SwiftUI
import AppKit
import ClipCore

public struct PopoverRootView: View {
    @ObservedObject public var viewModel: ClipBarViewModel
    @State private var keyMonitor: Any?
    private let refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            PasteboardService.shared.checkForChanges()
            viewModel.refreshClips()
            setupKeyboardMonitor()
        }
        .onReceive(refreshTimer) { _ in
            PasteboardService.shared.checkForChanges()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header Bar
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    // Spotlight-Style Glass Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor.opacity(0.9))

                        NoAutoFillSearchField(
                            placeholder: "Search clips (FTS5)...",
                            text: $viewModel.searchQuery,
                            onSubmit: {
                                viewModel.copySelected()
                            },
                            onArrowDown: {
                                viewModel.selectNext()
                            },
                            onArrowUp: {
                                viewModel.selectPrevious()
                            },
                            onEscape: {
                                if !viewModel.searchQuery.isEmpty {
                                    viewModel.searchQuery = ""
                                } else {
                                    StatusBarManager.shared.closePopover()
                                }
                            }
                        )
                        .frame(height: 20)

                        if !viewModel.searchQuery.isEmpty {
                            Button(action: { viewModel.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.75
                                    )
                            }
                    }

                    // Frosted Pause / Resume Button
                    Button(action: { viewModel.togglePause() }) {
                        Image(systemName: viewModel.settings.isPaused ? "pause.circle.fill" : "record.circle")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(viewModel.settings.isPaused ? .orange : .secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(viewModel.settings.isPaused ? Color.orange.opacity(0.18) : Color.white.opacity(0.05))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(viewModel.settings.isPaused ? Color.orange.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 0.5)
                                    }
                            )
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.settings.isPaused ? "Recording paused. Click to resume." : "Recording active. Click to pause.")
                }

                // Glass Segmented Capsule Switcher & Item Counter
                HStack {
                    HStack(spacing: 2) {
                        ForEach(FilterMode.allCases) { mode in
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    viewModel.filterMode = mode
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(mode.rawValue)
                                        .font(.system(size: 11, weight: viewModel.filterMode == mode ? .semibold : .medium))
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 4)
                                .background {
                                    if viewModel.filterMode == mode {
                                        RoundedRectangle(cornerRadius: 6.5)
                                            .fill(Color.white.opacity(0.18))
                                            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 6.5)
                                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                                            }
                                    }
                                }
                                .foregroundColor(viewModel.filterMode == mode ? .primary : .secondary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2.5)
                    .background(Color.black.opacity(0.18))
                    .cornerRadius(8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    }

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
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            // List of Clips or Empty State
            if viewModel.clips.isEmpty {
                emptyStateView
            } else {
                clipsListView
            }

            // Glass Keyboard Shortcuts Footer
            keyboardHelpFooter
        }
    }

    private var clipsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.stableId) { index, item in
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
                        .id(item.stableId)
                        .onAppear {
                            if index >= viewModel.clips.count - 4 {
                                viewModel.fetchNextPageIfNeeded()
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.selectedIndex) { newIndex in
                if newIndex >= 0 && newIndex < viewModel.clips.count {
                    let targetId = viewModel.clips[newIndex].stableId
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: viewModel.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(.secondary.opacity(0.35))

            Text(viewModel.searchQuery.isEmpty ? "No Clips Saved" : "No Matching Clips")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Text(viewModel.searchQuery.isEmpty ? "Copy text anywhere to begin saving history." : "Try a different search query.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyboardHelpFooter: some View {
        HStack(spacing: 9) {
            glassKeyLegend(keys: ["↑", "↓"], label: "Move")
            glassKeyLegend(keys: ["↵"], label: "Copy")
            glassKeyLegend(keys: ["⌘P"], label: "Pin")
            glassKeyLegend(keys: ["⌘⌫"], label: "Delete")
            glassKeyLegend(keys: ["⌘1-9"], label: "Quick")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Color.black.opacity(0.14)
                .overlay(alignment: .top) {
                    Divider().opacity(0.3)
                }
        )
    }

    private func glassKeyLegend(keys: [String], label: String) -> some View {
        HStack(spacing: 3.5) {
            HStack(spacing: 1.5) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(Color.white.opacity(0.09))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                                }
                                .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 0.5)
                        )
                }
            }
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.8))
        }
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
