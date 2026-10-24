import Foundation
import Combine
import SwiftUI
import ClipCore
import GRDB

public enum FilterMode: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case pinned = "Pinned"

    public var id: String { rawValue }
}

@MainActor
public final class ClipBarViewModel: ObservableObject {
    @Published public var clips: [ClipItem] = []
    @Published public var searchQuery: String = ""
    @Published public var filterMode: FilterMode = .all
    @Published public var selectedIndex: Int = 0
    @Published public var settings: AppSettings = .default
    @Published public var databaseStats: DatabaseStats?
    @Published public var copiedClipId: Int64?
    @Published public var showingSettings: Bool = false

    private let dbManager: DatabaseManager
    private let pasteboardService: PasteboardService
    private var clipsCancellable: AnyDatabaseCancellable?
    private var settingsCancellable: AnyDatabaseCancellable?
    private var searchDebounce: AnyCancellable?

    public init(
        databaseManager: DatabaseManager = .shared,
        pasteboardService: PasteboardService? = nil
    ) {
        self.dbManager = databaseManager
        self.pasteboardService = pasteboardService ?? PasteboardService.shared

        setupObservations()
        refreshStats()
    }

    public func setupObservations() {
        // Observe settings reactively
        settingsCancellable = dbManager.makeSettingsObservation().start(
            in: dbManager.dbWriter,
            onError: { error in
                print("Settings observation error: \(error)")
            },
            onChange: { [weak self] newSettings in
                Task { @MainActor [weak self] in
                    self?.settings = newSettings
                }
            }
        )

        // Observe clips reactively based on search query and filter mode
        restartClipsObservation()

        // Debounce search input and restart observation
        searchDebounce = Publishers.CombineLatest($searchQuery, $filterMode)
            .dropFirst()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedIndex = 0
                self?.restartClipsObservation()
            }
    }

    private func restartClipsObservation() {
        clipsCancellable?.cancel()

        let currentQuery = searchQuery
        let pinnedOnly = (filterMode == .pinned)

        clipsCancellable = dbManager.makeClipsObservation(
            searchQuery: { currentQuery },
            pinnedOnly: { pinnedOnly },
            limit: 150
        ).start(
            in: dbManager.dbWriter,
            onError: { error in
                print("Clips observation error: \(error)")
            },
            onChange: { [weak self] newClips in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.clips = newClips
                    if self.selectedIndex >= newClips.count {
                        self.selectedIndex = max(0, newClips.count - 1)
                    }
                    self.refreshStats()
                }
            }
        )
    }

    public func refreshStats() {
        if let stats = try? dbManager.getDatabaseStats() {
            self.databaseStats = stats
        }
    }

    // MARK: - Actions

    public func copyClip(_ item: ClipItem) {
        pasteboardService.copyToPasteboard(item: item)
        copiedClipId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedClipId == item.id {
                self?.copiedClipId = nil
            }
        }
    }

    public func copySelected() {
        guard !clips.isEmpty, selectedIndex >= 0, selectedIndex < clips.count else { return }
        copyClip(clips[selectedIndex])
    }

    public func copyQuick(index: Int) {
        guard index >= 0, index < clips.count else { return }
        copyClip(clips[index])
    }

    public func togglePin(_ item: ClipItem) {
        guard let id = item.id else { return }
        try? dbManager.togglePin(id: id)
    }

    public func togglePinSelected() {
        guard !clips.isEmpty, selectedIndex >= 0, selectedIndex < clips.count else { return }
        togglePin(clips[selectedIndex])
    }

    public func deleteClip(_ item: ClipItem) {
        guard let id = item.id else { return }
        try? dbManager.deleteClip(id: id)
    }

    public func deleteSelected() {
        guard !clips.isEmpty, selectedIndex >= 0, selectedIndex < clips.count else { return }
        deleteClip(clips[selectedIndex])
    }

    public func clearUnpinned() {
        try? dbManager.clearUnpinned()
        refreshStats()
    }

    public func updateSettings(_ newSettings: AppSettings) {
        try? dbManager.updateSettings(newSettings)
        self.settings = newSettings
    }

    public func togglePause() {
        var updated = settings
        updated.isPaused.toggle()
        updateSettings(updated)
    }

    // MARK: - Keyboard Navigation

    public func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    public func selectNext() {
        if selectedIndex < clips.count - 1 {
            selectedIndex += 1
        }
    }
}
