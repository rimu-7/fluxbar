import Foundation
import XCTest
@testable import PowerCore

final class PowerHelperManagerTests: XCTestCase {
    func testCommandPreservesLiteralArguments() throws {
        let arguments = ["folder with spaces", "owner's Mac", "double \"quotes\"", "$(exit 77)", "`exit 78`", "line\nbreak", "back\\slash"]
        let command = PowerHelperManager.shellCommand(executable: "/usr/bin/printf", arguments: ["%s\\n"] + arguments)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), arguments.joined(separator: "\n") + "\n")
    }

    func testAuthorizationScriptCompilesForUnusualAppPaths() {
        let script = PowerHelperManager.authorizationScript(
            executable: "/Applications/Owner's \"Apps\"/FluxBar.app/Contents/MacOS/com.fluxbar.powerd",
            arguments: ["install", "--limit", "80", "--enabled", "true"]
        )
        var error: NSDictionary?
        let compiled = NSAppleScript(source: script)?.compileAndReturnError(&error)
        XCTAssertEqual(compiled, true, "\(String(describing: error))")
    }

    func testExecutableInAQuotedAppFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FluxBar's \"Apps\" \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("helper")
        try "#!/bin/bash\nprintf '%s\\n' \"$@\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", PowerHelperManager.shellCommand(executable: executable.path, arguments: ["install", "80"])]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "install\n80\n")
    }
}
