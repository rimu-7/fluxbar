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

    /// The SMC connection is opened lazily on first use.
    public init() {}

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
        case appleSiliconM2M3M4 = "Apple Silicon (CHTE)"
        case appleSiliconM1     = "Apple Silicon M1 (CH0B/CH0C)"
        case intelBCLM          = "Intel Mac (BCLM)"
        case unsupported        = "Unsupported"
    }

    private var cachedGeneration: SMCHardwareGeneration?

    /// Probes the SMC once to find which charge-control keys this Mac has.
    public var detectedHardwareGeneration: SMCHardwareGeneration {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedGeneration { return cached }
        let gen: SMCHardwareGeneration
        if getKeyInfo("CHTE") != nil {
            gen = .appleSiliconM2M3M4
        } else if getKeyInfo("CH0B") != nil {
            gen = .appleSiliconM1
        } else if getKeyInfo("BCLM") != nil {
            gen = .intelBCLM
        } else {
            gen = .unsupported
        }
        // Don't cache a failed probe (e.g. SMC not reachable yet), try again next time.
        if gen != .unsupported { cachedGeneration = gen }
        return gen
    }

    // MARK: - Charge Control

    /// Pauses or resumes battery charging. Requires root; returns false when the write is refused.
    /// While paused on AC the Mac runs straight from the adapter.
    @discardableResult
    public func setChargingInhibited(_ inhibited: Bool, limitPercentage: Int = 80) -> Bool {
        switch detectedHardwareGeneration {
        case .appleSiliconM2M3M4:
            let ok = writeBytes("CHTE", bytes: inhibited ? [0x01, 0x00, 0x00, 0x00] : [0x00, 0x00, 0x00, 0x00])
            if ok { _ = writeUInt8("ACLC", value: inhibited ? 0x03 : 0x00) } // MagSafe LED: green while held
            return ok

        case .appleSiliconM1:
            let value: UInt8 = inhibited ? 0x02 : 0x00
            let b = writeUInt8("CH0B", value: value)
            let c = writeUInt8("CH0C", value: value)
            if b || c { _ = writeUInt8("ACLC", value: inhibited ? 0x03 : 0x00) }
            return b || c

        case .intelBCLM:
            // Intel SMC enforces the limit itself.
            let value = UInt8(clamping: inhibited ? ChargeLimitConfig.clampLimit(limitPercentage) : 100)
            let ok = writeUInt8("BCLM", value: value)
            return ok

        case .unsupported:
            return false
        }
    }

    /// Sets the MagSafe 3 LED (green, or back to automatic). Requires root.
    @discardableResult
    public func setMagSafeLED(green: Bool) -> Bool {
        return writeUInt8("ACLC", value: green ? 0x03 : 0x00)
    }

    /// True when this process can write the SMC (i.e. running as root).
    public var canWrite: Bool { geteuid() == 0 }
}
