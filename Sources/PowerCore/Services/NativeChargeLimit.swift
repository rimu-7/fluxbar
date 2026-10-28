import Foundation
import ObjectiveC

/// macOS's built-in charge limit (System Settings › Battery › Charge Limit).
///
/// macOS 27 (and the 15.8 / 26.7 security updates) locked the SMC charge-control keys that
/// third-party limiters used. On those Macs this is the supported way to hold the battery:
/// the firmware enforces it, including during sleep and after restarts, and it needs no root helper.
///
/// It talks to PowerUIAgent through `PowerUISmartChargeClient` in the PowerUI framework,
/// the same client System Settings uses. Must run as the logged-in user (the app or the CLI).
/// Apple only accepts 80–100% (System Settings offers 5% steps); 100 means "no limit".
public enum NativeChargeLimit {
    /// Lowest value Apple accepts. Lower values crash PowerUIAgent's client, so never send them.
    public static let minimumLimit = 80

    public enum NativeLimitError: LocalizedError {
        case unsupported
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupported: return "This Mac doesn't support the macOS charge limit."
            case .failed(let reason): return "macOS refused the charge limit: \(reason)"
            }
        }
    }

    /// True when this Mac offers the built-in charge limit.
    public static var isSupported: Bool {
        guard let client = Client.shared else { return false }
        return client.isSupported
    }

    /// Limits macOS accepts, e.g. [80, 85, 90, 95, 100].
    public static var availableLimits: [Int] {
        let fallback = [80, 85, 90, 95, 100]
        guard let client = Client.shared, let limits = client.availableLimits(), !limits.isEmpty else { return fallback }
        return limits.filter { $0 >= minimumLimit && $0 <= 100 }.sorted()
    }

    /// The current limit, 100 when no limit is set. Nil if it can't be read.
    public static func currentLimit() -> Int? {
        Client.shared?.currentLimit()
    }

    /// The closest limit macOS accepts (requests below 80 become 80).
    public static func nearestSupported(_ limit: Int, in limits: [Int] = availableLimits) -> Int {
        guard !limits.isEmpty else { return max(minimumLimit, min(100, limit)) }
        return limits.min { abs($0 - limit) < abs($1 - limit) || (abs($0 - limit) == abs($1 - limit) && $0 < $1) }!
    }

    /// Sets the limit (rounded to a supported value). Pass 100 to remove the limit.
    /// Returns the value that was applied.
    @discardableResult
    public static func set(_ limit: Int) throws -> Int {
        guard let client = Client.shared, client.isSupported else { throw NativeLimitError.unsupported }
        let value = limit >= 100 ? 100 : nearestSupported(limit)
        guard value >= minimumLimit && value <= 100 else { throw NativeLimitError.failed("out of range") }
        try client.setLimit(value)
        return value
    }

    // MARK: - PowerUI bridge

    /// Thin wrapper around the private `PowerUISmartChargeClient`. Every selector is checked before use,
    /// so a future macOS that renames it degrades to "unsupported" instead of crashing.
    private final class Client {
        static let shared: Client? = Client()

        private let client: SmartChargeClient
        private let lock = NSLock()

        private init?() {
            guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_LAZY) != nil,
                  let cls = NSClassFromString("PowerUISmartChargeClient") else { return nil }
            let required = ["initWithClientName:", "isMCLSupported", "getMCLLimitWithError:", "setMCLLimit:error:", "availableChargeLimitsWithError:"]
            guard required.allSatisfy({ class_respondsToSelector(cls, NSSelectorFromString($0)) }) else { return nil }
            // The class implements every method of the protocol (checked above); Swift then uses normal ObjC messaging and ARC.
            let type = unsafeBitCast(cls, to: SmartChargeClient.Type.self)
            client = type.init(clientName: "com.fluxbar.FluxBar")
        }

        var isSupported: Bool {
            lock.lock(); defer { lock.unlock() }
            return client.isMCLSupported
        }

        func currentLimit() -> Int? {
            lock.lock(); defer { lock.unlock() }
            var error: NSError?
            let value = Int(client.getMCLLimit(error: &error))
            guard error == nil, (1...100).contains(value) else { return nil }
            return value
        }

        func availableLimits() -> [Int]? {
            lock.lock(); defer { lock.unlock() }
            var error: NSError?
            guard let array = client.availableChargeLimits(error: &error), error == nil else { return nil }
            return array.map(\.intValue)
        }

        func setLimit(_ value: Int) throws {
            lock.lock(); defer { lock.unlock() }
            var error: NSError?
            let ok = client.setMCLLimit(UInt8(value), error: &error)
            if !ok || error != nil {
                throw NativeLimitError.failed(error?.localizedDescription ?? "unknown error")
            }
        }
    }
}

/// The subset of PowerUI's `PowerUISmartChargeClient` that FluxBar uses.
@objc private protocol SmartChargeClient: NSObjectProtocol {
    @objc(initWithClientName:) init(clientName: NSString)
    @objc var isMCLSupported: Bool { get }
    @objc(getMCLLimitWithError:) func getMCLLimit(error: NSErrorPointer) -> UInt8
    @objc(setMCLLimit:error:) func setMCLLimit(_ limit: UInt8, error: NSErrorPointer) -> Bool
    @objc(availableChargeLimitsWithError:) func availableChargeLimits(error: NSErrorPointer) -> [NSNumber]?
}

/// How this Mac's charge limit is enforced.
public enum ChargeLimitMethod: String, Codable, Sendable {
    /// FluxBar's root helper writes the SMC (any limit from 50 to 100%).
    case helper
    /// macOS's built-in charge limit (80–100%, no helper). Used when the SMC keys are locked.
    case macOS
    /// Neither is available.
    case unavailable

    /// Picks the method for this Mac. Prefers the helper because it supports lower limits.
    public static var current: ChargeLimitMethod {
        if SMCService.shared.detectedHardwareGeneration != .unsupported { return .helper }
        if NativeChargeLimit.isSupported { return .macOS }
        return .unavailable
    }

    /// Lowest limit this method can hold.
    public var minimumLimit: Int {
        self == .macOS ? NativeChargeLimit.minimumLimit : 50
    }
}
