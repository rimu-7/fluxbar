import Foundation
import IOKit

public struct SMCKeyInfo {
    public let dataSize: UInt32
    public let dataType: String
    public let dataAttributes: UInt8
}

/// Native System Management Controller (SMC) client for macOS
public final class SMCService: @unchecked Sendable {
    public static let shared = SMCService()

    private let lock = NSRecursiveLock()
    private var connection: io_connect_t = 0
    private var isConnectionOpen = false

    // MARK: - SMC Data Structures (Must match 80 bytes exactly)

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                   (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
    }

    private enum Selector: UInt8 {
        case handleYPCEvent = 2
        case readKey = 5
        case writeKey = 6
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    public init() {
        _ = openConnection()
    }

    deinit {
        closeConnection()
    }

    // MARK: - Connection Lifecycle

    @discardableResult
    public func openConnection() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isConnectionOpen && connection != 0 {
            return true
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            return false
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        if kr == kIOReturnSuccess && conn != 0 {
            self.connection = conn
            self.isConnectionOpen = true
            return true
        }
        return false
    }

    public func closeConnection() {
        lock.lock()
        defer { lock.unlock() }

        if isConnectionOpen && connection != 0 {
            IOServiceClose(connection)
            connection = 0
            isConnectionOpen = false
        }
    }

    // MARK: - FourCC Helpers

    public static func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for char in str.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    public static func codeToString(_ code: UInt32) -> String {
        let b0 = Character(UnicodeScalar((code >> 24) & 0xFF) ?? "?")
        let b1 = Character(UnicodeScalar((code >> 16) & 0xFF) ?? "?")
        let b2 = Character(UnicodeScalar((code >> 8) & 0xFF) ?? "?")
        let b3 = Character(UnicodeScalar(code & 0xFF) ?? "?")
        return "\(b0)\(b1)\(b2)\(b3)"
    }

    // MARK: - Key Inspection & Reading

    public func getKeyInfo(_ keyStr: String) -> SMCKeyInfo? {
        lock.lock()
        defer { lock.unlock() }

        guard openConnectionInternal() else { return nil }

        var input = SMCParamStruct()
        input.key = Self.fourCharCode(keyStr)
        input.data8 = Selector.getKeyInfo.rawValue

        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.size

        let res = IOConnectCallStructMethod(connection, UInt32(Selector.handleYPCEvent.rawValue), &input, size, &output, &size)
        guard res == kIOReturnSuccess && output.result == 0 else {
            return nil
        }

        return SMCKeyInfo(
            dataSize: output.keyInfo.dataSize,
            dataType: Self.codeToString(output.keyInfo.dataType),
            dataAttributes: output.keyInfo.dataAttributes
        )
    }

    public func readBytes(_ keyStr: String) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }

        guard openConnectionInternal() else { return nil }

        // 1. Query key info to learn expected size
        var input = SMCParamStruct()
        input.key = Self.fourCharCode(keyStr)
        input.data8 = Selector.getKeyInfo.rawValue

        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.size
        let res = IOConnectCallStructMethod(connection, UInt32(Selector.handleYPCEvent.rawValue), &input, size, &output, &size)
        guard res == kIOReturnSuccess && output.result == 0 else {
            return nil
        }

        let dataSize = Int(output.keyInfo.dataSize)
        guard dataSize > 0 && dataSize <= 32 else { return [] }

        // 2. Read key data
        input.keyInfo.dataSize = UInt32(dataSize)
        input.data8 = Selector.readKey.rawValue

        var readOut = SMCParamStruct()
        var readOutSize = MemoryLayout<SMCParamStruct>.size
        let readRes = IOConnectCallStructMethod(connection, UInt32(Selector.handleYPCEvent.rawValue), &input, size, &readOut, &readOutSize)
        guard readRes == kIOReturnSuccess && readOut.result == 0 else {
            return nil
        }

        return withUnsafeBytes(of: readOut.bytes) { rawPtr in
            Array(rawPtr.prefix(dataSize))
        }
    }

    public func readUInt8(_ keyStr: String) -> UInt8? {
        guard let bytes = readBytes(keyStr), !bytes.isEmpty else { return nil }
        return bytes[0]
    }

    public func readUInt16(_ keyStr: String) -> UInt16? {
        guard let bytes = readBytes(keyStr), bytes.count >= 2 else { return nil }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    public func readInt16(_ keyStr: String) -> Int16? {
        guard let u = readUInt16(keyStr) else { return nil }
        return Int16(bitPattern: u)
    }

    // MARK: - Key Writing

    public func writeBytes(_ keyStr: String, bytes: [UInt8]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard openConnectionInternal() else { return false }

        // 1. Get info to match type and size
        var input = SMCParamStruct()
        input.key = Self.fourCharCode(keyStr)
        input.data8 = Selector.getKeyInfo.rawValue

        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.size
        let res = IOConnectCallStructMethod(connection, UInt32(Selector.handleYPCEvent.rawValue), &input, size, &output, &size)
        guard res == kIOReturnSuccess && output.result == 0 else {
            return false
        }

        input.keyInfo.dataSize = UInt32(bytes.count)
        input.keyInfo.dataType = output.keyInfo.dataType
        input.data8 = Selector.writeKey.rawValue

        // Copy bytes to fixed tuple
        var tupleBytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                          UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                          UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                          UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
        withUnsafeMutableBytes(of: &tupleBytes) { ptr in
            for i in 0..<min(bytes.count, 32) {
                ptr[i] = bytes[i]
            }
        }
        input.bytes = tupleBytes

        var writeOut = SMCParamStruct()
        var writeSize = MemoryLayout<SMCParamStruct>.size
        let writeRes = IOConnectCallStructMethod(connection, UInt32(Selector.handleYPCEvent.rawValue), &input, size, &writeOut, &writeSize)

        return writeRes == kIOReturnSuccess && writeOut.result == 0
    }

    public func writeUInt8(_ keyStr: String, value: UInt8) -> Bool {
        return writeBytes(keyStr, bytes: [value])
    }

    private func openConnectionInternal() -> Bool {
        if isConnectionOpen && connection != 0 {
            return true
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        if kr == kIOReturnSuccess && conn != 0 {
            self.connection = conn
            self.isConnectionOpen = true
            return true
        }
        return false
    }

    // MARK: - Charge Limiter Hardware Inhibit & Resume

    /// Inhibit battery charging so Mac bypasses battery and runs on AC adapter
    @discardableResult
    public func setChargingInhibited(_ inhibited: Bool, limitPercentage: Int = 80) -> Bool {
        let inhibitByte: UInt8 = inhibited ? 0x01 : 0x00
        let enableByte: UInt8 = inhibited ? 0x00 : 0x01
        let limitByte: UInt8 = UInt8(clamping: limitPercentage)

        var directSuccess = false

        // Attempt direct SMC write (succeeds if running as root or with elevated entitlements)
        if writeUInt8("CHIB", value: inhibitByte) { directSuccess = true }
        if writeUInt8("CHCE", value: enableByte) { directSuccess = true }
        if writeUInt8("CHIE", value: inhibitByte) { directSuccess = true }
        if writeUInt8("B0CM", value: limitByte) { directSuccess = true }
        if writeUInt8("BCLM", value: limitByte) { directSuccess = true }

        if directSuccess {
            return true
        }

        // Apply via PowerHelperManager (wattbitd or notchkit helper)
        if PowerHelperManager.applyChargeLimit(inhibited ? limitPercentage : 100) {
            return true
        }

        // If direct write was unprivileged, invoke privileged helper if available
        return invokePrivilegedHelper(inhibited: inhibited, limit: limitPercentage)
    }

    /// Path where the privileged power helper is installed
    public static let helperPath = "/Library/PrivilegedHelperTools/com.walter.notchkit.power-helper"
    public static let fallbackHelperPath = "/usr/local/bin/notchkit-power-helper"

    public var isHelperInstalled: Bool {
        PowerHelperManager.isInstalled
    }

    private func invokePrivilegedHelper(inhibited: Bool, limit: Int) -> Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

        let execPath: String
        if FileManager.default.fileExists(atPath: Self.helperPath) {
            execPath = Self.helperPath
        } else if FileManager.default.fileExists(atPath: Self.fallbackHelperPath) {
            execPath = Self.fallbackHelperPath
        } else {
            return false
        }

        let action = inhibited ? "inhibit" : "resume"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = [action, "\(limit)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                if process.isRunning {
                    process.terminate()
                }
            }
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
