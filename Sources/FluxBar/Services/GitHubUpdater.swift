import AppKit
import SwiftUI
import ClipCore

/// Checks GitHub Releases for new FluxBar versions and installs them in place.
///
/// - Background checks run about once a day through `NSBackgroundActivityScheduler`, which lets macOS
///   pick an energy-efficient moment. They are silent unless a new version is found.
/// - The download is verified (checksum, bundle id, version, code signature) before anything is replaced.
/// - Installing hands off to a small script that swaps the app after FluxBar quits, then relaunches it.
@MainActor
final class GitHubUpdater: ObservableObject {
    static let shared = GitHubUpdater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case downloading(AvailableUpdate, progress: Double)
        case readyToInstall(AvailableUpdate, PreparedUpdate)
        case installing
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    /// User preference, on by default.
    @Published var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: Keys.automaticallyChecks)
            automaticallyChecks ? scheduleBackgroundChecks() : stopBackgroundChecks()
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? FluxBarInfo.version
    }

    /// Why this copy can't update itself (e.g. dev build, read-only folder), or nil.
    var installBlocker: String? { UpdateEngine.installBlocker(for: appURL) }

    private enum Keys {
        static let automaticallyChecks = "updates.automaticallyChecks"
        static let lastChecked = "updates.lastChecked"
        static let skippedVersion = "updates.skippedVersion"
    }

    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private let defaults = UserDefaults.standard
    private let appURL = UpdateEngine.installedAppURL()
    private var scheduler: NSBackgroundActivityScheduler?
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var window: NSWindow?
    private var windowObserver: NSObjectProtocol?

    private init() {
        defaults.register(defaults: [Keys.automaticallyChecks: true])
        automaticallyChecks = defaults.bool(forKey: Keys.automaticallyChecks)
        lastChecked = defaults.object(forKey: Keys.lastChecked) as? Date
    }

    // MARK: - Lifecycle

    /// Call once at launch.
    func start() {
        // Development builds (`swift run`) aren't in an app bundle and can't update themselves.
        guard appURL != nil, automaticallyChecks else { return }
        scheduleBackgroundChecks()

        // Catch up shortly after launch if the last check was more than a day ago.
        let overdue = lastChecked.map { Date().timeIntervalSince($0) > Self.checkInterval } ?? true
        if overdue {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard let self, self.automaticallyChecks else { return }
                self.checkForUpdates(userInitiated: false)
            }
        }
    }

    private func scheduleBackgroundChecks() {
        guard scheduler == nil, appURL != nil else { return }
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.fluxbar.FluxBar.update-check")
        scheduler.repeats = true
        scheduler.interval = Self.checkInterval
        scheduler.tolerance = 2 * 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                self?.checkForUpdates(userInitiated: false)
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    private func stopBackgroundChecks() {
        scheduler?.invalidate()
        scheduler = nil
    }

    // MARK: - Checking

    /// - Parameter userInitiated: from "Check for Updates": shows the window even when up to date or on
    ///   errors, and ignores "Skip This Version". Background checks stay silent unless there's an update.
    func checkForUpdates(userInitiated: Bool) {
        switch state {
        case .checking, .available, .downloading, .installing:
            // Already busy or already offering an update: just bring the window forward.
            if userInitiated { showWindow() }
            return
        case .readyToInstall:
            // Downloaded but postponed: remind (at most once per background check).
            showWindow()
            return
        case .idle, .upToDate, .error:
            break
        }

        checkTask?.cancel()
        if userInitiated { state = .checking; showWindow() }

        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let update = try await UpdateEngine.checkForUpdate(currentVersion: self.currentVersion)
                self.recordCheck()
                guard let update else {
                    self.state = userInitiated ? .upToDate : .idle
                    return
                }
                let skipped = self.defaults.string(forKey: Keys.skippedVersion)
                if !userInitiated && skipped == update.version {
                    self.state = .idle
                    return
                }
                self.state = .available(update)
                self.showWindow()
            } catch is CancellationError {
                return
            } catch {
                // Background failures (offline, rate limit) are silent; we'll try again tomorrow.
                self.state = userInitiated ? .error(error.localizedDescription) : .idle
            }
        }
    }

    private func recordCheck() {
        let now = Date()
        lastChecked = now
        defaults.set(now, forKey: Keys.lastChecked)
    }

    // MARK: - Download & install

    func downloadAndInstall() {
        guard case .available(let update) = state else { return }
        if let blocker = installBlocker {
            state = .error(blocker)
            return
        }

        state = .downloading(update, progress: 0)
        let bundleID = Bundle.main.bundleIdentifier ?? FluxBarInfo.bundleIdentifier

        downloadTask = Task { [weak self] in
            do {
                let prepared = try await UpdateEngine.prepare(update, expectedBundleID: bundleID) { fraction in
                    Task { @MainActor in GitHubUpdater.shared.reportProgress(fraction) }
                }
                guard let self, !Task.isCancelled else {
                    UpdateEngine.discard(prepared)
                    return
                }
                self.state = .readyToInstall(update, prepared)
            } catch is CancellationError {
                self?.state = .available(update)
            } catch {
                self?.state = .error(error.localizedDescription)
            }
        }
    }

    private func reportProgress(_ fraction: Double) {
        guard case .downloading(let update, let old) = state else { return }
        // Publish whole-percent steps only, to keep SwiftUI work minimal.
        if Int(fraction * 100) != Int(old * 100) { state = .downloading(update, progress: fraction) }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    /// Hands off to the swap script and quits. FluxBar relaunches as the new version.
    func installAndRelaunch() {
        guard case .readyToInstall(_, let prepared) = state, let appURL else { return }
        state = .installing
        do {
            try UpdateEngine.launchSwap(prepared, replacing: appURL,
                                        waitForPID: ProcessInfo.processInfo.processIdentifier, relaunch: true)
        } catch {
            state = .error(error.localizedDescription)
            return
        }
        NSApp.terminate(nil)
    }

    func skip(_ update: AvailableUpdate) {
        defaults.set(update.version, forKey: Keys.skippedVersion)
        dismiss()
    }

    /// "Later": close the window. Background checks will offer it again.
    func dismiss() {
        cancelDownload()
        if case .readyToInstall(_, let prepared) = state { UpdateEngine.discard(prepared) }
        switch state {
        case .checking, .installing: break
        default: state = .idle
        }
        window?.close()
    }

    func openReleasePage() {
        let url: URL
        switch state {
        case .available(let update), .downloading(let update, _), .readyToInstall(let update, _):
            url = update.release.htmlURL
        default:
            url = UpdateEngine.releasesPageURL
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Window

    /// A small standalone window, so the update prompt works even when the popover is closed.
    private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: UpdateAlertView(updater: self))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Software Update"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 460, height: 420))
            window.center()
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.windowWillClose() }
            }
            self.window = window
        }
        // FluxBar is a menu bar app (no Dock icon), so bring it forward explicitly.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func windowWillClose() {
        // Closing the window mid-download cancels it; a finished download is kept until relaunch.
        if case .downloading = state { cancelDownload() }
        switch state {
        // Closing an offer works like "Later": the next background check offers it again.
        case .upToDate, .error, .available: state = .idle
        default: break
        }
        // Free the SwiftUI hierarchy; it's rebuilt next time.
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        window = nil
    }
}
