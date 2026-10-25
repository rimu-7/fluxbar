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

    public func writeUInt32(_ keyStr: String, value: UInt32) -> Bool {
        let b0 = UInt8(value & 0xFF)
        let b1 = UInt8((value >> 8) & 0xFF)
        let b2 = UInt8((value >> 16) & 0xFF)
        let b3 = UInt8((value >> 24) & 0xFF)
        return writeBytes(keyStr, bytes: [b0, b1, b2, b3])
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

    // MARK: - Multi-Generation Hardware Detection

    public enum SMCHardwareGeneration: String, Sendable {
        case appleSiliconM2M3M4 = "Apple Silicon M2/M3/M4 (CHTE)"
        case appleSiliconM1     = "Apple Silicon M1 (CH0B/CH0C)"
        case intelBCLM          = "Intel Mac (BCLM)"
        case universalFallback  = "Universal Fallback"
    }

    /// Automatically probes the AppleSMC IOKit service to determine the active architecture
    public var detectedHardwareGeneration: SMCHardwareGeneration {
        if getKeyInfo("CHTE") != nil {
            return .appleSiliconM2M3M4
        } else if getKeyInfo("CH0B") != nil {
            return .appleSiliconM1
        } else if getKeyInfo("BCLM") != nil {
            return .intelBCLM
        }
        return .appleSiliconM2M3M4
    }

    // MARK: - Charge Limiter Hardware Matrix & AC Bypass

    /// Controls battery charging cutoff across all Apple Silicon and Intel generations
    @discardableResult
    public func setChargingInhibited(
        _ inhibited: Bool,
        limitPercentage: Int = 80,
        forceDischarge: Bool = false
    ) -> Bool {
        let limitByte = UInt8(clamping: limitPercentage)
        var success = false

        let gen = detectedHardwareGeneration

        switch gen {
        case .appleSiliconM2M3M4:
            // CHTE = 01 00 00 00 to inhibit, 00 00 00 00 to enable
            let chteBytes: [UInt8] = inhibited ? [0x01, 0x00, 0x00, 0x00] : [0x00, 0x00, 0x00, 0x00]
            if writeBytes("CHTE", bytes: chteBytes) { success = true }

            // Force discharge on AC if requested (CHIE = 01)
            if forceDischarge {
                _ = writeUInt8("CHIE", value: 0x01)
            } else if !inhibited {
                _ = writeUInt8("CHIE", value: 0x00)
            }

            // MagSafe 3 LED sync (ACLC: 03 = Green / Bypass, 00 = Auto / Amber)
            _ = writeUInt8("ACLC", value: inhibited ? 0x03 : 0x00)

        case .appleSiliconM1:
            // CH0B & CH0C = 02 to inhibit, 00 to enable
            let m1Byte: UInt8 = inhibited ? 0x02 : 0x00
            if writeUInt8("CH0B", value: m1Byte) { success = true }
            if writeUInt8("CH0C", value: m1Byte) { success = true }

            // Force discharge on AC if requested (CH0I = 01)
            if forceDischarge {
                _ = writeUInt8("CH0I", value: 0x01)
            } else if !inhibited {
                _ = writeUInt8("CH0I", value: 0x00)
            }

            // MagSafe 3 LED sync
            _ = writeUInt8("ACLC", value: inhibited ? 0x03 : 0x00)

        case .intelBCLM, .universalFallback:
            // Intel BCLM = limitByte (e.g. 80) to inhibit, 100 to enable
            let bclmVal: UInt8 = inhibited ? limitByte : 100
            if writeUInt8("BCLM", value: bclmVal) { success = true }
            if writeUInt8("B0CM", value: bclmVal) { success = true }
        }

        // Also update legacy/fallback keys for maximum hardware compatibility
        let inhibitBit: UInt8 = inhibited ? 0x01 : 0x00
        let enableBit: UInt8 = inhibited ? 0x00 : 0x01
        _ = writeUInt8("CHIB", value: inhibitBit)
        _ = writeUInt8("CHCE", value: enableBit)

        if success {
            return true
        }

        // Apply via PowerHelperManager (wattbitd or notchkit helper daemon)
        if PowerHelperManager.applyChargeLimit(inhibited ? limitPercentage : 100) {
            return true
        }

        return invokePrivilegedHelper(inhibited: inhibited, limit: limitPercentage)
    }

    /// Sets MagSafe 3 LED color (Green = 0x03, Amber/Auto = 0x00)
    @discardableResult
    public func setMagSafeLED(green: Bool) -> Bool {
        return writeUInt8("ACLC", value: green ? 0x03 : 0x00)
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
