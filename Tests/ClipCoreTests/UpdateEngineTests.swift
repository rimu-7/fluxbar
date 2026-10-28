import Foundation
import XCTest
@testable import ClipCore

@objcMembers
final class UpdateEngineTests: XCTestCase {

    // MARK: - Versions

    public func testVersionComparison() throws {
        XCTAssertTrue(AppVersion.isNewer("v1.2.1", than: "1.2.0"))
        XCTAssertTrue(AppVersion.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(AppVersion.isNewer("2.0", than: "1.99.99"))
        XCTAssertTrue(AppVersion.isNewer("V1.3.0", than: "v1.2.9"))
        XCTAssertFalse(AppVersion.isNewer("v1.2.0", than: "1.2.0"))
        XCTAssertFalse(AppVersion.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(AppVersion.isNewer("1.1.9", than: "1.2.0"))
        XCTAssertFalse(AppVersion.isNewer("1.2.0-beta", than: "1.2.0"))
        XCTAssertEqual(AppVersion.normalized(" v1.2.0 "), "1.2.0")
    }

    // MARK: - GitHub response

    private func releaseJSON(tag: String, prerelease: Bool = false, assets: [String] = ["FluxBar.zip", "FluxBar.zip.sha256", "FluxBar.dmg"]) -> Data {
        let assetJSON = assets.map {
            #"{"name":"\#($0)","size":5000000,"browser_download_url":"https://github.com/rimu-7/fluxbar/releases/download/\#(tag)/\#($0)"}"#
        }.joined(separator: ",")
        let json = #"""
        {"tag_name":"\#(tag)","name":"FluxBar","body":"## What's Changed\n* Fix battery limit","html_url":"https://github.com/rimu-7/fluxbar/releases/tag/\#(tag)",
         "published_at":"2026-10-28T14:27:26Z","draft":false,"prerelease":\#(prerelease),"assets":[\#(assetJSON)],"extra_field":123}
        """#
        return Data(json.utf8)
    }

    public func testDecodesReleaseAndFindsAssets() throws {
        let release = try UpdateEngine.decodeRelease(releaseJSON(tag: "v1.2.1"))
        XCTAssertEqual(release.version, "1.2.1")
        XCTAssertEqual(release.asset(named: "FluxBar.zip")?.size, 5_000_000)
        XCTAssertTrue((release.publishedAt) != nil)

        let update = try UpdateEngine.update(from: release, currentVersion: "1.2.0")
        XCTAssertEqual(update?.version, "1.2.1")
        XCTAssertEqual(update?.currentVersion, "1.2.0")
        XCTAssertEqual(update?.checksum?.name, "FluxBar.zip.sha256")
        XCTAssertEqual(update?.notes, "## What's Changed\n* Fix battery limit")
    }

    public func testNoUpdateWhenCurrentOrPrerelease() throws {
        let same = try UpdateEngine.decodeRelease(releaseJSON(tag: "v1.2.0"))
        XCTAssertTrue((try UpdateEngine.update(from: same, currentVersion: "1.2.0")) == nil)
        XCTAssertTrue((try UpdateEngine.update(from: same, currentVersion: "1.3.0")) == nil)

        let beta = try UpdateEngine.decodeRelease(releaseJSON(tag: "v2.0.0", prerelease: true))
        XCTAssertTrue((try UpdateEngine.update(from: beta, currentVersion: "1.2.0")) == nil)
    }

    public func testMissingZipIsAnError() throws {
        let release = try UpdateEngine.decodeRelease(releaseJSON(tag: "v9.0.0", assets: ["FluxBar.dmg"]))
        do {
            _ = try UpdateEngine.update(from: release, currentVersion: "1.2.0")
            XCTAssertTrue(false, "expected missingAsset")
        } catch {
            XCTAssertEqual(error as? UpdateError, .missingAsset("FluxBar.zip"))
        }
    }

    public func testChecksumParsingAndHashing() throws {
        let hash = String(repeating: "aB", count: 32)
        XCTAssertEqual(UpdateEngine.parseChecksum("\(hash)  FluxBar.zip\n"), hash.lowercased())
        XCTAssertTrue((UpdateEngine.parseChecksum("not-a-hash  FluxBar.zip")) == nil)
        XCTAssertTrue((UpdateEngine.parseChecksum("")) == nil)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fluxbar-hash-\(UUID().uuidString)")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try UpdateEngine.sha256(of: file), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    // MARK: - Swap script

    /// Runs the real swap script on dummy bundles: waits for a process, swaps, trashes the old app.
    public func testSwapScriptReplacesAppAfterProcessExits() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("fluxbar-swap-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let apps = root.appendingPathComponent("Apps With Spaces", isDirectory: true)
        let work = root.appendingPathComponent("work", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createDirectory(at: work.appendingPathComponent("New/FluxBar.app"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let dest = apps.appendingPathComponent("FluxBar.app")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: dest.appendingPathComponent("marker"))
        let newApp = work.appendingPathComponent("New/FluxBar.app")
        try Data("new".utf8).write(to: newApp.appendingPathComponent("marker"))

        let script = work.appendingPathComponent("swap.sh")
        try UpdateEngine.swapScript.write(to: script, atomically: true, encoding: .utf8)

        // Stand-in for the running app: exits after ~0.5 s.
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sleep")
        waiter.arguments = ["0.5"]
        try waiter.run()

        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/bash")
        swap.arguments = [script.path, String(waiter.processIdentifier), newApp.path, dest.path, "0", work.path]
        swap.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        try swap.run()
        swap.waitUntilExit()
        waiter.waitUntilExit()

        XCTAssertEqual(swap.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertFalse(fm.fileExists(atPath: newApp.path))
        XCTAssertFalse(fm.fileExists(atPath: work.path), "work folder is cleaned up on success")
        let trashed = try fm.contentsOfDirectory(atPath: home.appendingPathComponent(".Trash").path)
        XCTAssertEqual(trashed.count, 1)
        XCTAssertTrue(trashed.first?.hasPrefix("FluxBar ") ?? false)
        let leftovers = try fm.contentsOfDirectory(atPath: apps.path)
        XCTAssertEqual(leftovers, ["FluxBar.app"])
    }

    public func testSwapScriptRestoresOldAppWhenNewOneIsMissing() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("fluxbar-swap-\(UUID().uuidString)", isDirectory: true)
        let work = root.appendingPathComponent("work", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let dest = root.appendingPathComponent("FluxBar.app")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: dest.appendingPathComponent("marker"))

        let script = work.appendingPathComponent("swap.sh")
        try UpdateEngine.swapScript.write(to: script, atomically: true, encoding: .utf8)

        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/bash")
        swap.arguments = [script.path, "0", work.appendingPathComponent("missing.app").path, dest.path, "0", work.path]
        try swap.run()
        swap.waitUntilExit()

        XCTAssertTrue(swap.terminationStatus != 0)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("marker"), encoding: .utf8), "old")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path).sorted(), ["FluxBar.app", "work"])
    }

    public func testInstallBlockers() throws {
        XCTAssertTrue((UpdateEngine.installBlocker(for: nil)) != nil)
        XCTAssertTrue((UpdateEngine.installBlocker(for: URL(fileURLWithPath: "/System/Applications/FluxBar.app"))) != nil)
        let writable = FileManager.default.temporaryDirectory.appendingPathComponent("FluxBar.app")
        XCTAssertTrue((UpdateEngine.installBlocker(for: writable)) == nil)
    }
}
