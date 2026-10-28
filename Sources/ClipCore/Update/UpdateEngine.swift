import Foundation
import CryptoKit
import Security
import Darwin

// FluxBar's self-updater, without third-party dependencies.
//
//   1. check     GET api.github.com/repos/rimu-7/fluxbar/releases/latest and compare versions
//   2. download  FluxBar.zip + FluxBar.zip.sha256 into a private temporary folder
//   3. verify    SHA-256 checksum, bundle id, version and code signature of the new app
//   4. install   a small shell script waits for FluxBar to quit, swaps the app bundle,
//                moves the old one to the Trash and relaunches
//
// User data lives in ~/Library/Application Support, so replacing the bundle is all an update needs.
// Used by the app (GitHubUpdater) and by `flux update`.

// MARK: - GitHub API models

/// The parts of a GitHub release FluxBar needs.
public struct GitHubRelease: Decodable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    /// Release notes (Markdown).
    public let body: String?
    public let htmlURL: URL
    public let publishedAt: Date?
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    public struct Asset: Decodable, Sendable, Equatable {
        public let name: String
        public let size: Int
        public let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    /// "v1.2.1" → "1.2.1"
    public var version: String { AppVersion.normalized(tagName) }

    public func asset(named name: String) -> Asset? {
        assets.first { $0.name == name }
    }
}

/// An update that is newer than the running version and has a downloadable app.
public struct AvailableUpdate: Sendable, Equatable {
    public let release: GitHubRelease
    public let currentVersion: String
    public let zip: GitHubRelease.Asset
    public let checksum: GitHubRelease.Asset?

    public var version: String { release.version }
    public var notes: String { (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Versions

public enum AppVersion {
    /// Strips a leading "v" and whitespace: "v1.2.0" → "1.2.0".
    public static func normalized(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.first == "v" || v.first == "V" { v.removeFirst() }
        return v
    }

    /// Numeric parts of a version, ignoring any "-beta" / "+build" suffix: "1.10.0-rc1" → [1, 10, 0].
    static func components(_ version: String) -> [Int] {
        let core = normalized(version).split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        return core.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// True when `candidate` is a higher version than `current` ("1.10.0" > "1.9.9", "1.2" == "1.2.0").
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - Errors

public enum UpdateError: LocalizedError, Equatable {
    case network(String)
    case rateLimited
    case noReleases
    case badResponse(Int)
    case missingAsset(String)
    case downloadTooLarge
    case checksumMismatch
    case extractionFailed
    case invalidApp(String)
    case notInstallable(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .network(let message): return "Couldn't reach GitHub: \(message)"
        case .rateLimited: return "GitHub is limiting requests right now. Try again in an hour."
        case .noReleases: return "No FluxBar releases were found."
        case .badResponse(let code): return "GitHub returned an unexpected response (HTTP \(code))."
        case .missingAsset(let name): return "The latest release has no \(name)."
        case .downloadTooLarge: return "The download is larger than expected, so it was stopped."
        case .checksumMismatch: return "The download didn't match its checksum, so it wasn't installed."
        case .extractionFailed: return "The downloaded update couldn't be unpacked."
        case .invalidApp(let reason): return "The downloaded app failed verification: \(reason)"
        case .notInstallable(let reason): return reason
        case .installFailed(let reason): return "The update couldn't be installed: \(reason)"
        }
    }
}

// MARK: - Engine

public enum UpdateEngine {
    public static let repository = "rimu-7/fluxbar"
    public static let zipAssetName = "FluxBar.zip"
    public static let checksumAssetName = "FluxBar.zip.sha256"
    public static var releasesPageURL: URL { URL(string: "https://github.com/\(repository)/releases/latest")! }

    /// Refuse anything implausibly large (the app zip is ~5 MB).
    static let maxDownloadBytes: Int64 = 200 * 1024 * 1024

    // MARK: Check

    /// Fetches the latest published (non-draft, non-prerelease) release.
    public static func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("FluxBar/\(FluxBarInfo.version)", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse(0) }
        switch http.statusCode {
        case 200: break
        case 404: throw UpdateError.noReleases
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.badResponse(http.statusCode)
        }
        return try decodeRelease(data)
    }

    public static func decodeRelease(_ data: Data) throws -> GitHubRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.badResponse(200)
        }
    }

    /// Returns the update if `release` is newer than `currentVersion` and ships an app zip.
    public static func update(from release: GitHubRelease, currentVersion: String) throws -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              AppVersion.isNewer(release.tagName, than: currentVersion) else { return nil }
        guard let zip = release.asset(named: zipAssetName) else { throw UpdateError.missingAsset(zipAssetName) }
        return AvailableUpdate(release: release, currentVersion: AppVersion.normalized(currentVersion),
                               zip: zip, checksum: release.asset(named: checksumAssetName))
    }

    /// Checks GitHub. Nil when already up to date.
    public static func checkForUpdate(currentVersion: String) async throws -> AvailableUpdate? {
        try update(from: try await fetchLatestRelease(), currentVersion: currentVersion)
    }

    // MARK: Download & verify

    /// Downloads, verifies and unpacks the update. Returns the verified `FluxBar.app` inside a private
    /// temporary folder. `progress` receives 0…1 (on an arbitrary thread).
    public static func prepare(
        _ update: AvailableUpdate,
        expectedBundleID: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PreparedUpdate {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluxBarUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        do {
            // 1. The checksum file is tiny; fetch it first so a bad release fails fast.
            var expectedHash: String?
            if let checksum = update.checksum {
                let data = try await downloadSmall(checksum.browserDownloadURL)
                expectedHash = parseChecksum(String(decoding: data, as: UTF8.self))
                guard expectedHash != nil else { throw UpdateError.checksumMismatch }
            }

            // 2. The app.
            let zipURL = workDir.appendingPathComponent(zipAssetName)
            try await Downloader.download(update.zip.browserDownloadURL, to: zipURL,
                                          maxBytes: maxDownloadBytes, progress: progress)

            // 3. Integrity.
            if let expectedHash {
                guard try sha256(of: zipURL) == expectedHash else { throw UpdateError.checksumMismatch }
            }

            // 4. Unpack with ditto, which keeps the code signature and extended attributes intact.
            let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
            try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path], error: .extractionFailed)
            try? FileManager.default.removeItem(at: zipURL)

            let app = extractDir.appendingPathComponent("FluxBar.app", isDirectory: true)
            try validate(app: app, expectedBundleID: expectedBundleID, expectedVersion: update.version)
            return PreparedUpdate(app: app, workDirectory: workDir, version: update.version)
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            throw error
        }
    }

    /// "e3b0…  FluxBar.zip" → "e3b0…" (lowercase hex), nil if malformed.
    public static func parseChecksum(_ text: String) -> String? {
        guard let first = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first else { return nil }
        let hash = first.lowercased()
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hash
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Checks the unpacked app is FluxBar, is the advertised version, and has an intact signature.
    /// If the running app is signed by a Developer ID team, the update must be signed by the same team.
    static func validate(app: URL, expectedBundleID: String, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app), let info = bundle.infoDictionary else {
            throw UpdateError.invalidApp("FluxBar.app is missing from the download")
        }
        guard info["CFBundleIdentifier"] as? String == expectedBundleID else {
            throw UpdateError.invalidApp("unexpected bundle identifier")
        }
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        guard AppVersion.normalized(version) == AppVersion.normalized(expectedVersion) else {
            throw UpdateError.invalidApp("version \(version) doesn't match the release")
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.invalidApp("no code signature")
        }
        var requirement: SecRequirement?
        if let team = currentTeamIdentifier() {
            // Same publisher as the running app (only possible with Developer ID builds).
            let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
            guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
                throw UpdateError.invalidApp("couldn't build the signing requirement")
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        guard status == errSecSuccess else {
            throw UpdateError.invalidApp("code signature check failed (\(status))")
        }
    }

    /// Team ID of the running process, nil for ad-hoc signed builds.
    static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func downloadSmall(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("FluxBar/\(FluxBarInfo.version)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw UpdateError.badResponse(code) }
            guard data.count < 4096 else { throw UpdateError.downloadTooLarge }
            return data
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
    }

    // MARK: Install

    /// Where the running app (or the app containing this command line tool) is installed.
    /// Nil when not running from a `.app` bundle (e.g. `swift run`).
    public static func installedAppURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        ]
        for candidate in candidates {
            var url = candidate.resolvingSymlinksInPath()
            while url.path != "/" {
                if url.pathExtension == "app" { return url }
                url.deleteLastPathComponent()
            }
        }
        return nil
    }

    /// Explains why the app at `appURL` can't be replaced in place, or nil if it can.
    public static func installBlocker(for appURL: URL?) -> String? {
        guard let appURL else {
            return "This copy of FluxBar isn't running from an app bundle. Download the latest release instead."
        }
        let folder = appURL.deletingLastPathComponent()
        if appURL.path.contains("/AppTranslocation/") {
            return "Move FluxBar to your Applications folder first, then check for updates again."
        }
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            return "FluxBar can't write to \(folder.path). Update with the terminal installer instead."
        }
        return nil
    }

    /// The script that swaps the app after FluxBar quits. Paths are passed as arguments, never pasted
    /// into the script text, so spaces or quotes in folder names can't break it.
    ///
    /// Arguments: pid-to-wait-for (0 = don't wait), new app, destination app, relaunch (1/0), work folder.
    public static let swapScript = """
    #!/bin/bash
    # FluxBar updater: replaces FluxBar.app once FluxBar has quit, then relaunches it.
    set -u
    PID="$1"; NEW="$2"; DEST="$3"; RELAUNCH="$4"; WORK="$5"
    exec >>"$WORK/update.log" 2>&1
    echo "$(date '+%F %T') updating $DEST"

    # 1. Wait (up to 30 s) for FluxBar to quit.
    if [ "$PID" != "0" ]; then
      for _ in $(seq 1 150); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.2
      done
      if kill -0 "$PID" 2>/dev/null; then
        echo "FluxBar is still running; update cancelled"
        exit 1
      fi
    fi

    # 2. Move the old app aside, but keep it until the new one is in place.
    BACKUP="${DEST%.app}.previous-$$.app"
    if [ -e "$DEST" ] && ! mv "$DEST" "$BACKUP"; then
      echo "could not move the old app"
      [ "$RELAUNCH" = "1" ] && open "$DEST"
      exit 1
    fi

    # 3. Move the new app in. On failure put the old one back.
    if ! mv "$NEW" "$DEST"; then
      echo "could not install the new app; restoring the old one"
      [ -e "$BACKUP" ] && mv "$BACKUP" "$DEST"
      [ "$RELAUNCH" = "1" ] && open "$DEST"
      exit 1
    fi
    xattr -dr com.apple.quarantine "$DEST" 2>/dev/null

    # 4. Old version to the Trash (deleted outright if the Trash isn't usable).
    if [ -e "$BACKUP" ]; then
      TRASHED="$HOME/.Trash/FluxBar $(date '+%Y-%m-%d %H.%M.%S').app"
      mv "$BACKUP" "$TRASHED" 2>/dev/null || rm -rf "$BACKUP"
    fi

    # 5. Relaunch and clean up.
    [ "$RELAUNCH" = "1" ] && open "$DEST"
    echo "done"
    rm -rf "$WORK"
    """

    /// Starts the swap script in the background and returns immediately.
    /// The caller should quit right after (the script waits for `waitForPID`).
    public static func launchSwap(
        _ prepared: PreparedUpdate,
        replacing destination: URL,
        waitForPID: pid_t,
        relaunch: Bool
    ) throws {
        if let blocker = installBlocker(for: destination) { throw UpdateError.notInstallable(blocker) }

        let script = prepared.workDirectory.appendingPathComponent("swap.sh")
        do {
            try swapScript.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            script.path,
            String(waitForPID),
            prepared.app.path,
            destination.path,
            relaunch ? "1" : "0",
            prepared.workDirectory.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }

    /// Distributed notification that asks a running FluxBar to quit so `flux update` can replace it.
    public static let quitForUpdateNotification = Notification.Name("com.fluxbar.FluxBar.quitForUpdate")

    /// Process IDs of FluxBar instances running from `appURL`.
    public static func runningPIDs(of appURL: URL) -> [pid_t] {
        let executable = appURL.appendingPathComponent("Contents/MacOS/FluxBar").resolvingSymlinksInPath().path
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(Int(filled)).filter { pid in
            guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
            return String(cString: buffer) == executable
        }
    }

    /// Deletes a prepared update that won't be installed.
    public static func discard(_ prepared: PreparedUpdate) {
        try? FileManager.default.removeItem(at: prepared.workDirectory)
    }

    // MARK: Helpers

    private static func run(_ tool: String, _ arguments: [String], error: UpdateError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw error }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw error }
    }
}

/// A downloaded, verified update waiting to be installed.
public struct PreparedUpdate: Sendable, Equatable {
    /// The verified FluxBar.app in a private temporary folder.
    public let app: URL
    /// Temporary folder holding everything for this update (removed after install).
    public let workDirectory: URL
    public let version: String
}

// MARK: - Download with progress

/// URLSession download task wrapped for async/await, with progress and a size cap.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let maxBytes: Int64
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private let lock = NSLock()

    private init(destination: URL, maxBytes: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.maxBytes = maxBytes
        self.progress = progress
    }

    static func download(_ url: URL, to destination: URL, maxBytes: Int64,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = Downloader(destination: destination, maxBytes: maxBytes, progress: progress)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 15 * 60
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("FluxBar/\(FluxBarInfo.version)", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.lock.lock()
                delegate.continuation = continuation
                delegate.lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let continuation else { return }
        finished = true
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maxBytes || totalBytesExpectedToWrite > maxBytes {
            downloadTask.cancel()
            finish(.failure(UpdateError.downloadTooLarge))
            return
        }
        if totalBytesExpectedToWrite > 0 {
            progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this method returns, so move it now.
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            finish(.failure(UpdateError.badResponse(code)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            progress(1)
            finish(.success(()))
        } catch {
            finish(.failure(UpdateError.network(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code == .cancelled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(UpdateError.network(error.localizedDescription)))
            }
        } else {
            // Success is reported from didFinishDownloadingTo; this is a no-op if that already ran.
            finish(.failure(UpdateError.network("the download ended unexpectedly")))
        }
    }
}
