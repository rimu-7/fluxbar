import Darwin
import Foundation

/// Low-level BSD socket sampler that queries kernel network interface statistics via `getifaddrs`.
public struct NetworkByteSampler: Sendable {

    public init() {}

    /// Queries total transmitted and received bytes for the specified network interface name (or all active non-loopback interfaces if nil).
    public func queryBytes(forInterface targetName: String? = nil) -> (bytesIn: UInt64, bytesOut: UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return (0, 0)
        }
        defer { freeifaddrs(first) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let ptr = cursor {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)

            let isTarget: Bool
            if let target = targetName, !target.isEmpty {
                isTarget = (name == target)
            } else {
                // Ignore loopback, virtual bridges, and down links
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                isTarget = isUp && !isLoopback
            }

            if isTarget && ifa.ifa_addr != nil && ifa.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ifa.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(ifData.ifi_ibytes)
                    totalOut += UInt64(ifData.ifi_obytes)
                }
            }
            cursor = ifa.ifa_next
        }

        return (totalIn, totalOut)
    }

    /// Computes transfer delta between two byte counts, handling 32-bit hardware counter rollover gracefully.
    public static func computeDelta(current: UInt64, previous: UInt64) -> UInt64 {
        if current >= previous {
            return current - previous
        } else {
            // Hardware 32-bit counter rollover
            let max32 = UInt64(UInt32.max)
            return (max32 - previous) + current + 1
        }
    }
}
