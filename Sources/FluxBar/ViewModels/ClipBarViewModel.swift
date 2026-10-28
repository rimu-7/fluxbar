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
    public static let shared = ClipBarViewModel()

    // Ultra-lightweight metadata-only projection for SwiftUI (~200 bytes per row instead of 50KB+)
    @Published public var clips: [ClipListSummary] = []
    @Published public var searchQuery: String = ""
    @Published public var filterMode: FilterMode = .all
    @Published public var selectedIndex: Int = 0
    @Published public var settings: AppSettings = .default
    @Published public var databaseStats: DatabaseStats?
    @Published public var copiedClipId: Int64?
    @Published public var showingSettings: Bool = false

    public private(set) var hasMorePages: Bool = true
    public private(set) var isPopoverVisible: Bool = false

    public var dbPath: String? { dbManager.dbPath }

    private let dbManager: DatabaseManager
    private let pasteboardService: PasteboardService
    private var settingsCancellable: AnyDatabaseCancellable?
    private var searchDebounce: AnyCancellable?
    private var clipRecordedSub: AnyCancellable?
    private var isLoadingNextPage: Bool = false

    public init(
        databaseManager: DatabaseManager = .shared,
        pasteboardService: PasteboardService? = nil
    ) {
        self.dbManager = databaseManager
        let service = pasteboardService ?? PasteboardService.shared
        self.pasteboardService = service

        setupObservations()
        refreshClips()
        refreshStats()

        // Real-time notification hooks: only refresh UI if popover is actively visible
        service.onClipRecorded = { [weak self] _ in
            guard let self = self, self.isPopoverVisible else { return }
            self.refreshClips()
        }

        clipRecordedSub = NotificationCenter.default.publisher(for: .clipSuiteDidRecordClip)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.isPopoverVisible else { return }
                self.refreshClips()
            }
    }

    public func setPopoverVisible(_ visible: Bool) {
        self.isPopoverVisible = visible
        if visible {
            refreshClips()
            refreshStats()
        } else {
            releaseCachedSearchResults()
        }
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

        // Debounce search input and refresh first page
        searchDebounce = Publishers.CombineLatest($searchQuery, $filterMode)
            .dropFirst()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedIndex = 0
                self?.refreshClips()
            }
    }

    // MARK: - Keyset Pagination (Page 1)

    public func refreshClips() {
        let currentQuery = searchQuery
        let pinnedOnly = (filterMode == .pinned)
        do {
            let items = try dbManager.fetchNextPage(
                after: nil,
                searchQuery: currentQuery,
                pinnedOnly: pinnedOnly,
                limit: 25
            )
            self.clips = items
            self.hasMorePages = (items.count >= 25)
            if self.selectedIndex >= items.count {
                self.selectedIndex = max(0, items.count - 1)
            }
            self.refreshStats()
        } catch {
            print("Failed to fetch first page of clips: \(error)")
        }
    }

    // MARK: - Keyset Pagination (Subsequent Pages)

    public func fetchNextPageIfNeeded() {
        guard isPopoverVisible, !isLoadingNextPage, hasMorePages,
              let lastItem = clips.last else { return }

        isLoadingNextPage = true
        let currentQuery = searchQuery
        let pinnedOnly = (filterMode == .pinned)

        do {
            let nextPage = try dbManager.fetchNextPage(
                after: lastItem,
                searchQuery: currentQuery,
                pinnedOnly: pinnedOnly,
                limit: 25
            )
            if nextPage.isEmpty {
                self.hasMorePages = false
            } else {
                self.clips.append(contentsOf: nextPage)
                self.hasMorePages = (nextPage.count >= 25)
            }
        } catch {
            print("Failed to fetch next page of clips: \(error)")
        }
        isLoadingNextPage = false
    }

    /// Releases cached search results when popover closes to keep memory <15 MB
    public func releaseCachedSearchResults() {
        if clips.count > 25 {
            clips = Array(clips.prefix(25))
        }
    }

    public func refreshStats() {
        if let stats = try? dbManager.getDatabaseStats() {
            self.databaseStats = stats
        }
    }

    // MARK: - Actions (Lazy Full Fetch)

    /// Lazy fetch: only query the full content or blob column for a single ID at the exact millisecond user clicks Copy
    public func copyClip(_ item: ClipListSummary) {
        guard let id = item.id else { return }
        do {
            if let fullClip = try dbManager.fetchClip(id: id) {
                pasteboardService.copyToPasteboard(item: fullClip)
                copiedClipId = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    if self?.copiedClipId == id {
                        self?.copiedClipId = nil
                    }
                }
            }
        } catch {
            print("Failed to fetch full clip #\(id) for pasteboard copy: \(error)")
        }
    }

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

    public func togglePin(_ item: ClipListSummary) {
        guard let id = item.id else { return }
        do {
            try dbManager.togglePin(id: id)
            refreshClips()
        } catch {
            print("Failed to toggle pin for clip #\(id): \(error)")
        }
    }

    public func togglePin(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            try dbManager.togglePin(id: id)
            refreshClips()
        } catch {
            print("Failed to toggle pin for clip #\(id): \(error)")
        }
    }

    public func togglePinSelected() {
        guard !clips.isEmpty, selectedIndex >= 0, selectedIndex < clips.count else { return }
        togglePin(clips[selectedIndex])
    }

    public func deleteClip(_ item: ClipListSummary) {
        guard let id = item.id else { return }
        do {
            try dbManager.deleteClip(id: id)
            refreshClips()
        } catch {
            print("Failed to delete clip #\(id): \(error)")
        }
    }

    public func deleteClip(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            try dbManager.deleteClip(id: id)
            refreshClips()
        } catch {
            print("Failed to delete clip #\(id): \(error)")
        }
    }

    public func deleteSelected() {
        guard !clips.isEmpty, selectedIndex >= 0, selectedIndex < clips.count else { return }
        deleteClip(clips[selectedIndex])
    }

    public func clearUnpinned() {
        do {
            try dbManager.clearUnpinned()
            refreshClips()
        } catch {
            print("Failed to clear unpinned: \(error)")
        }
    }

    public func deleteAllClips() {
        do {
            try dbManager.deleteAllClips()
            refreshClips()
        } catch {
            print("Failed to delete all clips: \(error)")
        }
    }

    public func optimizeStorage() {
        do {
            try dbManager.optimizeDatabase()
            refreshStats()
        } catch {
            print("Failed to optimize database: \(error)")
        }
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
